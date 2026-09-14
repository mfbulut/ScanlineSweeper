@echo off
cd /d "%~dp0"

slangc shader.slang -target spirv -o shader.spv
