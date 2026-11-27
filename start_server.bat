@echo off
setlocal
if not defined GODOT_BIN set "GODOT_BIN=godot"
"%GODOT_BIN%" --headless --path "%~dp0." server.tscn
