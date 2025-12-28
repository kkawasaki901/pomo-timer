-- lua/pomo-timer/init.lua
local M = {}

-- =================================================
-- config (internal)
-- =================================================
local defaults = {
	notify = true,
	enable_white_noise = false,
}

local options = vim.deepcopy(defaults)

function M.setup(opts)
	opts = opts or {}
	options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
end

-- =================================================
-- beep
-- =================================================
local function beep_n(freq, count)
	vim.fn.jobstart({
		"python",
		"-c",
		string.format(
			"import time,winsound\nfor _ in range(%d):\n winsound.Beep(%d,120)\n time.sleep(0.25)\n",
			count,
			freq
		),
	}, { detach = true })
end

local function beep_start()
	beep_n(880, 3)
end

local function beep_done()
	beep_n(440, 10)
end

-- =================================================
-- spinner
-- =================================================
local spinner_timer
local notify_id
local frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local frame_i = 1

local function start_spinner()
	if not options.notify then
		return
	end

	frame_i = 1
	notify_id = vim.notify("TIMER WORKING " .. frames[frame_i], vim.log.levels.INFO)

	spinner_timer = vim.loop.new_timer()
	spinner_timer:start(
		0,
		120,
		vim.schedule_wrap(function()
			frame_i = frame_i % #frames + 1
			notify_id = vim.notify("TIMER WORKING " .. frames[frame_i], vim.log.levels.INFO, { replace = notify_id })
		end)
	)
end

local function stop_spinner()
	if spinner_timer then
		spinner_timer:stop()
		spinner_timer:close()
		spinner_timer = nil
	end
end

-- =================================================
-- white noise
-- =================================================
local noise_job = nil

local function start_noise()
	if noise_job then
		return
	end
	noise_job = vim.fn.jobstart({
		"python",
		"-c",
		[[
import numpy as np, sounddevice as sd, signal
SAMPLERATE=44100
VOLUME=0.01
running=True
def handler(sig,frame):
    global running; running=False
signal.signal(signal.SIGTERM,handler)
signal.signal(signal.SIGINT,handler)
def callback(outdata,frames,time,status):
    if not running: raise sd.CallbackStop()
    outdata[:] = np.random.randn(frames,1)*VOLUME
with sd.OutputStream(samplerate=SAMPLERATE,channels=1,callback=callback):
    while running: sd.sleep(100)
]],
	}, { detach = false })
end

local function stop_noise()
	if noise_job then
		vim.fn.jobstop(noise_job)
		noise_job = nil
	end
end

vim.api.nvim_create_autocmd("VimLeavePre", {
	group = vim.api.nvim_create_augroup("PomoTimerWhiteNoise", { clear = true }),
	callback = function()
		stop_noise()
	end,
})

-- =================================================
-- notifier (for pomo.nvim)
-- =================================================
local TestNotifier = {}
TestNotifier.__index = TestNotifier

function TestNotifier.new(timer, _)
	return setmetatable({ timer = timer }, TestNotifier)
end

function TestNotifier.tick(_) end

function TestNotifier.start(_)
	start_spinner()
	beep_start()

	if options.enable_white_noise then
		start_noise()
	end
end

function TestNotifier.done(_)
	stop_spinner()
	vim.notify("TIMER DONE!", vim.log.levels.WARN)

	if options.enable_white_noise then
		stop_noise()
	end

	beep_done()
end

-- =================================================
-- exports
-- =================================================
M.TestNotifier = TestNotifier

return M
