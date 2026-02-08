local M = {}

M.config = {
	-- Keybindings under LazyVim buffer menu (<leader>b)
	keymap_merge = "<leader>bm",
	keymap_diff = "<leader>bD",
	-- Auto-prompt on FileChangedShell when buffer is modified
	auto_prompt = true,
	-- Auto-merge silently on change (only if clean, aborts on conflicts)
	auto_merge = false,
}

-- Shadow base directory for storing file snapshots
local shadow_dir = vim.fn.stdpath("cache") .. "/swap-merge-shadows"

-- Get shadow path for a file
local function get_shadow_path(file)
	-- Create a unique path based on the file's absolute path
	local encoded = file:gsub("/", "%%"):gsub(":", "%%")
	return shadow_dir .. "/" .. encoded
end

-- Update shadow base file (called on buffer open and save)
local function update_shadow(file)
	if vim.fn.filereadable(file) == 0 then
		return
	end
	vim.fn.mkdir(shadow_dir, "p")
	local shadow = get_shadow_path(file)
	vim.fn.system("cp " .. vim.fn.shellescape(file) .. " " .. vim.fn.shellescape(shadow))
end

-- Three-way merge: buffer (yours) + disk (theirs) + shadow (base)
-- Returns: true if merged cleanly, false if conflicts or error
function M.merge(opts)
	opts = opts or {}
	local silent = opts.silent or false

	local buf = vim.api.nvim_get_current_buf()
	local file = vim.fn.expand("%:p")
	local shadow = get_shadow_path(file)

	-- Check if buffer is modified
	if not vim.bo[buf].modified then
		-- No local changes, just reload
		vim.cmd("edit!")
		update_shadow(file)
		if not silent then
			vim.notify("Reloaded (no local changes)")
		end
		return true
	end

	-- Check if shadow exists
	if vim.fn.filereadable(shadow) == 0 then
		if not silent then
			vim.notify("No shadow base found, cannot merge. Try :e! to reload.", vim.log.levels.WARN)
		end
		return false
	end

	-- Save buffer content to temp file (yours)
	local yours = vim.fn.tempname()
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	vim.fn.writefile(lines, yours)

	-- Run git merge-file: yours + base (shadow) + theirs (disk)
	-- -p outputs to stdout instead of modifying file
	local result = vim.fn.system(
		"git merge-file -p "
			.. vim.fn.shellescape(yours)
			.. " "
			.. vim.fn.shellescape(shadow)
			.. " "
			.. vim.fn.shellescape(file)
	)
	local exit_code = vim.v.shell_error

	-- Clean up temp file
	vim.fn.delete(yours)

	if exit_code < 0 then
		if not silent then
			vim.notify("Merge failed: " .. result, vim.log.levels.ERROR)
		end
		return false
	end

	-- Conflicts detected - abort if silent mode
	if exit_code > 0 then
		if silent then
			vim.notify("Auto-merge aborted: conflicts detected. Use " .. M.config.keymap_merge .. " to merge manually.", vim.log.levels.WARN)
			return false
		else
			-- Interactive mode: show conflicts
			local merged_lines = vim.split(result, "\n", { plain = true })
			if #merged_lines > 0 and merged_lines[#merged_lines] == "" then
				table.remove(merged_lines)
			end
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, merged_lines)
			vim.notify(string.format("Merged with %d conflict(s) - search for <<<<<<<", exit_code), vim.log.levels.WARN)
			vim.fn.search("<<<<<<<", "w")
			return false
		end
	end

	-- Clean merge
	local merged_lines = vim.split(result, "\n", { plain = true })
	if #merged_lines > 0 and merged_lines[#merged_lines] == "" then
		table.remove(merged_lines)
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, merged_lines)

	-- Auto-write to checkpoint the merge
	vim.cmd("silent write!")
	-- Update shadow to the new merged content
	update_shadow(file)
	vim.notify("Merged cleanly and saved")
	return true
end

-- Open three-way diff view
function M.diff()
	local file = vim.fn.expand("%:p")
	local shadow = get_shadow_path(file)

	-- Save buffer content to temp file (yours)
	local yours = vim.fn.tempname() .. "_YOURS"
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	vim.fn.writefile(lines, yours)

	-- Use shadow as base, copy to temp with label
	local base = vim.fn.tempname() .. "_BASE"
	if vim.fn.filereadable(shadow) == 1 then
		vim.fn.system("cp " .. vim.fn.shellescape(shadow) .. " " .. vim.fn.shellescape(base))
	else
		vim.fn.writefile({}, base)
	end

	-- Copy theirs (disk version)
	local theirs = vim.fn.tempname() .. "_THEIRS"
	vim.fn.system("cp " .. vim.fn.shellescape(file) .. " " .. vim.fn.shellescape(theirs))

	-- Open three-way diff in new tab
	vim.cmd("tabnew " .. vim.fn.fnameescape(yours))
	vim.cmd("vertical diffsplit " .. vim.fn.fnameescape(base))
	vim.cmd("vertical diffsplit " .. vim.fn.fnameescape(theirs))
	vim.cmd("wincmd t") -- go to first window (yours)

	vim.notify("Left: yours | Middle: base (last save) | Right: theirs (disk)")
end

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

	-- Track shadow base files
	vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
		pattern = "*",
		callback = function()
			local file = vim.fn.expand("%:p")
			-- Only track real files, not special buffers
			if vim.bo.buftype == "" and vim.fn.filereadable(file) == 1 then
				update_shadow(file)
			end
		end,
	})

	-- Keymaps under buffer menu
	vim.keymap.set("n", M.config.keymap_merge, M.merge, { desc = "Merge external changes" })
	vim.keymap.set("n", M.config.keymap_diff, M.diff, { desc = "Diff external changes (3-way)" })

	-- User commands
	vim.api.nvim_create_user_command("SwapMerge", M.merge, { desc = "Three-way merge external changes" })
	vim.api.nvim_create_user_command("SwapDiff", M.diff, { desc = "Three-way diff external changes" })

	-- Handle FileChangedShell events
	if M.config.auto_merge or M.config.auto_prompt then
		vim.api.nvim_create_autocmd("FileChangedShell", {
			pattern = "*",
			callback = function(ev)
				local buf = ev.buf

				-- Only act if buffer is modified
				if not vim.bo[buf].modified then
					return
				end

				-- Set v:fcs_choice to prevent default dialog
				vim.v.fcs_choice = ""

				vim.schedule(function()
					if M.config.auto_merge then
						-- Silent auto-merge, aborts on conflicts
						M.merge({ silent = true })
					elseif M.config.auto_prompt then
						-- Interactive prompt
						local choice = vim.fn.confirm(
							"File changed externally. You have unsaved changes.",
							"&Merge (3-way)\n&Diff view\n&Reload (lose changes)\n&Ignore",
							1
						)
						if choice == 1 then
							M.merge()
						elseif choice == 2 then
							M.diff()
						elseif choice == 3 then
							vim.cmd("edit!")
						end
					end
				end)
			end,
		})
	end
end

return M
