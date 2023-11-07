local actions = require("telescope.actions")
local actions_state = require("telescope.actions.state")
local toggleterm_ui = require("toggleterm.ui")
local util = require("util")
local Terminal = require("toggleterm.terminal").Terminal

local M = {}

--- Create a new terminal and open it. If exit_on_action is true, focus it.
--- @param prompt_bufnr number The buffer number of the telescope prompt.
--- @param exit_on_action boolean Whether to exit the telescope buffer when the action executes.
function M.create_term(prompt_bufnr, exit_on_action)
	-- forward declare `term` so it can be used inside `on_open_terminal`.
	local term

	local function on_open_terminal()
		if not exit_on_action then
			vim.schedule(function()
				-- set origin window to current term before switching back to telescope
				-- this ensures the cursor is moved to the correct term window after closing a term
				toggleterm_ui.set_origin_window()
				util.focus_on_telescope(prompt_bufnr)
				util.refresh_picker(prompt_bufnr, term)
				-- remove the on_open callback to avoid potential side effects in future actions.
				term.on_open = nil
			end)
		end
	end

	term = Terminal:new({ on_open = on_open_terminal })

	if exit_on_action then
		actions.close(prompt_bufnr)

		-- the autocommand setup in telescope/init.lua that starts insert mode on leaving the telescope buffer
		-- won't work here since the cursor may move to a non-toggleterm buftype for a brief moment while the
		-- toggleterm buffer is being created
		util.start_insert_mode()
	else
		util.focus_on_origin_win()
	end

	term:open()
end

--- Create and name a new terminal and open it. If exit_on_action is true, focus it.
--- @param prompt_bufnr number The buffer number of the telescope prompt.
--- @param exit_on_action boolean Whether to exit the telescope buffer when the action executes.
function M.create_and_name_term(prompt_bufnr, exit_on_action)
	local prompt = "Name terminal: "

	vim.ui.input({ prompt = prompt }, function(name)
		util.clear_command_line()
		if name and #name > 0 then
			local term
			local function on_open_terminal()
				if not exit_on_action then
					vim.schedule(function()
						-- set origin window to current term before switching back to telescope
						-- this ensures the cursor is moved to the correct term window after closing a term
						toggleterm_ui.set_origin_window()
						util.focus_on_telescope(prompt_bufnr)
						util.refresh_picker(prompt_bufnr, term)
						-- remove the on_open callback to avoid potential side effects in future actions.
						term.on_open = nil
					end)
				end
			end

			term = Terminal:new({ display_name = name, on_open = on_open_terminal })

			if exit_on_action then
				actions.close(prompt_bufnr)
				-- the autocommand setup in telescope/init.lua that starts insert mode on leaving the telescope buffer
				-- won't work here since the cursor may move to a non-toggleterm buftype for a brief moment while the
				-- toggleterm buffer is being created
				util.start_insert_mode()
			else
				util.focus_on_origin_win()
			end
			term:open()
		end
	end)
end

--- Open a terminal. If exit_on_action is true, focus it.
--- @param prompt_bufnr number The buffer number of the telescope prompt.
--- @param exit_on_action boolean Whether to exit the telescope buffer when the action executes.
function M.open_term(prompt_bufnr, exit_on_action)
	local selection = actions_state.get_selected_entry()
	if selection == nil then
		return
	end

	local term = selection.value

	if exit_on_action then
		actions.close(prompt_bufnr)
		if not term:is_open() then
			term:open()
		end
		term:focus()
		return
	end

	util.focus_on_origin_win()
	if not term:is_open() then
		term:open()
	end

	util.focus_on_telescope(prompt_bufnr)
	util.refresh_picker(prompt_bufnr, term)
end

--- Delete a buffer, with an option to force deletion.
--- @param bufnr number The buffer number to delete.
--- @param force boolean Whether to force deletion or not.
local function delete_buffer(bufnr, force)
	local ok, err = pcall(function()
		vim.api.nvim_buf_delete(bufnr, { force = force })
	end)

	if not ok then
		local msg = "Error while deleting buffer: " .. tostring(err)
		vim.notify(msg, vim.log.levels.WARN)
	end
end

--- Delete a terminal.
--- @param prompt_bufnr number The buffer number of the telescope prompt.
--- @param exit_on_action boolean Whether to exit the telescope buffer when the action executes.
function M.delete_term(prompt_bufnr, exit_on_action)
	local selection = actions_state.get_selected_entry()
	if selection == nil then
		return
	end

	local term = selection.value

	-- If exit_on_action is true, we want to close the picker and shutdown the terminal.
	if exit_on_action then
		actions.close(prompt_bufnr)
		term:shutdown()
		return
	end

	-- This prevents toggleterm from doing additional processing that would cause the telescope
	-- window to close. Toggleterm's __handle_exit is called when a terminal buffer is deleted,
	-- which calls term:close(). term.close() calls close_split(), which changes window focus
	-- and causes telescope to exit. See toggleterm's terminal.lua:__handle_exit and ui.lua:close_split.
	term.close_on_exit = false

	-- Focus the origin window before deleting the buffer to avoid Telescope from closing.
	util.focus_on_origin_win()

	-- Check if the buffer type is 'terminal', which requires 'force' when deleting.
	local force = vim.api.nvim_buf_get_option(selection.bufnr, "buftype") == "terminal"

	-- Delete the buffer associated with the terminal.
	delete_buffer(selection.bufnr, force)

	-- Reset the origin window in the toggleterm UI after deletion.
	toggleterm_ui.set_origin_window()

	util.focus_on_telescope(prompt_bufnr)

	-- Refresh the picker to reflect the changes in the list of terminals.
	-- Pass a boolean flag indicating that an item has been deleted
	util.refresh_picker(prompt_bufnr, selection, true)
end

--- Toggle a terminal open or closed. If toggling open and exit_on_action is true, focus it.
--- @param prompt_bufnr number The buffer number of the telescope prompt.
--- @param exit_on_action boolean Whether to exit the telescope buffer when the action executes.
function M.toggle_term(prompt_bufnr, exit_on_action)
	local current_picker = actions_state.get_current_picker(prompt_bufnr)

	local selection = actions_state.get_selected_entry()
	if selection == nil then
		return
	end

	local term = selection.value

	if exit_on_action then
		actions.close(prompt_bufnr)
		term:toggle()
		return
	end

	util.focus_on_origin_win()
	if term:is_open() then
		term:close()
		current_picker.original_win_id = toggleterm_ui.get_origin_window()
	else
		term:open()
		current_picker.original_win_id = term.window
	end

	util.focus_on_telescope(prompt_bufnr)
	util.refresh_picker(prompt_bufnr, term)
end

--- Rename a terminal. If exit_on_action is true, focus it.
--- @param prompt_bufnr number The buffer number of the telescope prompt.
--- @param exit_on_action boolean Whether to exit the telescope buffer when the action executes.
function M.rename_term(prompt_bufnr, exit_on_action)
	local selection = actions_state.get_selected_entry()
	if selection == nil then
		return
	end

	local term = selection.value

	local prompt = string.format("Rename terminal %s: ", selection.term_name)
	vim.ui.input({ prompt = prompt }, function(name)
		util.clear_command_line()
		if name and #name > 0 then
			-- rename terminal within toggleterm
			term.display_name = name

			if exit_on_action then
				actions.close(prompt_bufnr)
				term:focus()
			else
				local current_picker = actions_state.get_current_picker(prompt_bufnr)
				local finder, new_row_number = util.create_finder(term.id)
				current_picker:refresh(finder, { reset_prompt = false })

				util.set_selection_row(current_picker, new_row_number)
			end
		end
	end)
end

return M
