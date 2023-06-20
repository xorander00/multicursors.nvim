local api = vim.api

local highlight = require 'multicursors.highlight'
local config = require 'multicursors.config'

local ns_id = api.nvim_create_namespace 'multicursors'

---@param any any
local function debug(any)
    if config.DEBUG_MODE then
        vim.notify(vim.inspect(any), vim.log.levels.DEBUG)
    end
end

local M = {}

--- Moves the cursor to pos and marks current cursor position in jumplist
--- htpps://github.com/neovim/neovim/issues/20793
---@param pos any[]
---@param current any[]?
local function move_cursor(pos, current)
    if not current then
        current = api.nvim_win_get_cursor(0)
    end

    api.nvim_buf_set_mark(0, "'", current[1], current[2], {})
    api.nvim_win_set_cursor(0, { pos[1], pos[2] })
    vim.cmd [[ redraw! ]]
end

--- creates a extmark for the the match
--- doesn't create a duplicate mark
---@param match Match
---@return integer id of created mark
local create_extmark = function(match)
    local marks = api.nvim_buf_get_extmarks(
        0,
        ns_id,
        { match.row - 1, match.start },
        { match.row - 1, match.finish },
        {}
    )
    if #marks > 0 then
        debug('found ' .. #marks .. ' duplicate marks:')
        return marks[1][1]
    end

    return api.nvim_buf_set_extmark(0, ns_id, match.row - 1, match.start, {
        end_row = match.row - 1,
        end_col = match.finish,
        hl_group = 'MultiCursor',
    })
end

local ESC = vim.api.nvim_replace_termcodes('<Esc>', true, false, true)

--- gets a single char from user
--- when intrupted returns nil
---@return string?
local function get_char()
    local ok, key = pcall(vim.fn.getcharstr)
    if not ok then
        return nil
    end

    return key
end

--- Returns the first match for pattern after a offset in a string
---@param string string
---@param pattern string
---@param row_idx integer
---@param offset integer
---@return integer? id of created mark
local find_next_match = function(string, pattern, row_idx, offset)
    if not string or string == '' then
        return
    end

    if offset ~= 0 then
        string = string:sub(offset + 1, -1)
    end

    local match = vim.fn.matchstrpos(string, '\\<' .. pattern .. '\\>')
    -- -1 range means not found
    if match[2] == -1 and match[3] == -1 then
        return nil
    end

    -- add offset to match position index
    match.start = match[2] + offset
    match.finish = match[3] + offset

    -- jump the cursor to last char of match
    match.row = row_idx
    move_cursor({ row_idx, match.finish }, nil)

    return create_extmark(match)
end

-- creates a mark for word under the cursor
---@return integer?,string?
M.find_cursor_word = function()
    local line = api.nvim_get_current_line()
    if not line then
        return
    end

    local cursor = api.nvim_win_get_cursor(0)
    local left = vim.fn.matchstrpos(line:sub(1, cursor[2] + 1), [[\k*$]])
    local right = vim.fn.matchstrpos(line:sub(cursor[2] + 1), [[^\k*]])

    if left == -1 and right == -1 then
        return
    end

    local word = {
        row = cursor[1],
        start = left[2],
        finish = right[3] + cursor[2],
    }

    local mark_id = create_extmark(word)
    move_cursor { cursor[1], cursor[2] + right[3] }

    return mark_id, left[1] .. right[1]:sub(2)
end

--- skips current match and jumps to next
---@param pattern string
---@param current_mark? integer
M.skip_forward = function(pattern, current_mark)
    if not current_mark then
        return
    end
    api.nvim_buf_del_extmark(0, ns_id, current_mark)
    M.find_next(pattern)
end

---finds next match and marks it
---@param pattern string
---@return integer? id of next match mark
M.find_next = function(pattern)
    ---@type integer[]
    local cursor = api.nvim_win_get_cursor(0)
    local line_count = api.nvim_buf_line_count(0)

    local row_idx = cursor[1]
    -- search the same line as cursor with cursor col as offset cursor
    local line = api.nvim_buf_get_lines(0, row_idx - 1, row_idx, true)[1]
    local mark_id = find_next_match(line, pattern, row_idx, cursor[2])
    if mark_id then
        return mark_id
    end

    -- search from cursor to end of buffer for pattern
    for idx = row_idx + 1, line_count, 1 do
        line = api.nvim_buf_get_lines(0, idx - 1, idx, true)[1]
        mark_id = find_next_match(line, pattern, idx, 0)
        if mark_id then
            return mark_id
        end
    end

    -- when we didn't find the pattern we start searching again
    -- from start of the buffer
    for idx = 0, cursor[1], 1 do
        line = api.nvim_buf_get_lines(0, idx - 1, idx, true)[1]
        mark_id = find_next_match(line, pattern, idx, 0)
        if mark_id then
            return mark_id
        end
    end
end

M.start = function()
    local last_mark, w = M.find_cursor_word()

    --TODO when nil just add the cursor???
    if not w or not last_mark then
        return
    end

    while true do
        local key = get_char()
        if not key then
            M.exit()
            return
        end

        debug 'listening for mod selector'
        if key == ESC then
            M.exit()
            return
        elseif key == 'n' then
            last_mark = M.find_next(w)
        elseif key == 'q' then
            last_mark = M.skip_forward(w, last_mark)
        end
    end
end

M.exit = function()
    api.nvim_buf_clear_namespace(0, ns_id, 0, -1)
end

return M
