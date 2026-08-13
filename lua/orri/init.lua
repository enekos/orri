--- orri — stream the live buffer to the native viewer over a unix socket.
---
--- No Node, no HTTP server, no browser: `vim.uv` is libuv, built into Neovim,
--- so this plugin has no dependencies at all.

local M = {}

local uv = vim.uv or vim.loop

M.config = {
  --- Viewer binary, resolved on $PATH.
  bin = 'orri',
  --- Socket path. Defaults to $ORRI_SOCKET, then /tmp/orri-$USER.sock.
  socket = nil,
  --- Milliseconds to coalesce keystrokes before resending.
  debounce = 40,
}

local state = {
  pipe = nil,
  connected = false,
  connecting = false,
  bufnr = nil,
  attached = {},
  timer = nil,
  augroup = nil,
}

local read_start

local function socket_path()
  return M.config.socket
    or vim.env.ORRI_SOCKET
    or ('/tmp/orri-%s.sock'):format(vim.env.USER or 'default')
end

local function send(msg)
  local pipe = state.pipe
  if not (state.connected and pipe) then
    return
  end
  local ok, encoded = pcall(vim.json.encode, msg)
  if not ok then
    return
  end
  -- Encoded JSON escapes its own newlines, so one frame is always one line.
  pipe:write(encoded .. '\n', function(err)
    if err then
      vim.schedule(function()
        M.disconnect()
      end)
    end
  end)
end

local function send_doc(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  send({
    type = 'doc',
    text = table.concat(lines, '\n') .. '\n',
    path = vim.api.nvim_buf_get_name(bufnr),
  })
end

--- Coalesces bursts of keystrokes into one resend.
local function schedule_doc(bufnr)
  if state.timer then
    pcall(function()
      state.timer:stop()
      state.timer:close()
    end)
    state.timer = nil
  end

  local timer = uv.new_timer()
  state.timer = timer
  timer:start(M.config.debounce, 0, function()
    pcall(function()
      timer:stop()
      timer:close()
    end)
    if state.timer == timer then
      state.timer = nil
    end
    vim.schedule(function()
      send_doc(bufnr)
    end)
  end)
end

local function handle_frame(line)
  local ok, msg = pcall(vim.json.decode, line)
  if not ok or type(msg) ~= 'table' then
    return
  end

  -- Clicking a block in the viewer moves the cursor here.
  if msg.type == 'jump' and msg.line and state.bufnr then
    if not vim.api.nvim_buf_is_valid(state.bufnr) then
      return
    end
    local win = vim.fn.bufwinid(state.bufnr)
    if win == -1 then
      return
    end
    local last = vim.api.nvim_buf_line_count(state.bufnr)
    local line_nr = math.max(1, math.min(math.floor(msg.line), last))
    pcall(vim.api.nvim_win_set_cursor, win, { line_nr, 0 })
  end
end

read_start = function(pipe)
  local pending = ''
  pipe:read_start(function(err, chunk)
    if err or not chunk then
      vim.schedule(function()
        M.disconnect()
      end)
      return
    end

    pending = pending .. chunk
    while true do
      local newline = pending:find('\n')
      if not newline then
        break
      end
      local line = pending:sub(1, newline - 1)
      pending = pending:sub(newline + 1)
      vim.schedule(function()
        handle_frame(line)
      end)
    end
  end)
end

--- Connects, retrying `attempts` times so a cold app launch has time to bind.
local function connect(attempts, cb)
  if state.connecting then
    return
  end
  state.connecting = true

  local pipe = uv.new_pipe(false)
  pipe:connect(socket_path(), function(err)
    state.connecting = false

    if err then
      pcall(function()
        pipe:close()
      end)
      vim.schedule(function()
        if attempts > 1 then
          vim.defer_fn(function()
            connect(attempts - 1, cb)
          end, 150)
        else
          cb(false, err)
        end
      end)
      return
    end

    state.pipe = pipe
    state.connected = true
    read_start(pipe)
    vim.schedule(function()
      cb(true)
    end)
  end)
end

local function attach(bufnr)
  if state.attached[bufnr] then
    return
  end
  state.attached[bufnr] = true

  vim.api.nvim_buf_attach(bufnr, false, {
    -- M0 resends the whole buffer; the byte deltas this hands us are what M2
    -- will use for incremental re-parse.
    on_bytes = function()
      if state.bufnr ~= bufnr or not state.connected then
        return
      end
      schedule_doc(bufnr)
    end,
    on_detach = function()
      state.attached[bufnr] = nil
    end,
  })
end

local function setup_autocmds(bufnr)
  state.augroup = vim.api.nvim_create_augroup('Orri', { clear = true })

  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
    group = state.augroup,
    buffer = bufnr,
    callback = function()
      send({ type = 'cursor', line = vim.api.nvim_win_get_cursor(0)[1] })
    end,
  })

  -- Cheap safety net: a write always reconciles, even if a delta was missed.
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = state.augroup,
    buffer = bufnr,
    callback = function()
      send_doc(bufnr)
    end,
  })
end

local function launch()
  if vim.fn.executable(M.config.bin) == 0 then
    vim.notify(
      ('orri: %q is not on $PATH'):format(M.config.bin),
      vim.log.levels.ERROR
    )
    return false
  end
  vim.fn.jobstart({ M.config.bin, '--socket', socket_path() }, { detach = true })
  return true
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
end

--- Opens (or focuses) the viewer and starts streaming the current buffer.
function M.open(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  state.bufnr = bufnr

  local function ready()
    send_doc(bufnr)
    attach(bufnr)
    setup_autocmds(bufnr)
  end

  if state.connected then
    ready()
    return
  end

  connect(1, function(ok)
    if ok then
      ready()
      return
    end
    if not launch() then
      return
    end
    -- ~6s of retries covers a cold first launch.
    connect(40, function(connected, err)
      if connected then
        ready()
      else
        vim.notify(
          'orri: could not reach the viewer: ' .. tostring(err),
          vim.log.levels.ERROR
        )
      end
    end)
  end)
end

function M.disconnect()
  if state.timer then
    pcall(function()
      state.timer:stop()
      state.timer:close()
    end)
    state.timer = nil
  end

  if state.pipe then
    pcall(function()
      state.pipe:read_stop()
    end)
    pcall(function()
      state.pipe:close()
    end)
  end
  state.pipe = nil
  state.connected = false

  if state.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
    state.augroup = nil
  end
end

function M.toggle()
  if state.connected then
    M.disconnect()
  else
    M.open()
  end
end

return M
