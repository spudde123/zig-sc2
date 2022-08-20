call zig build -Dtarget=x86_64-linux -Drelease-safe

MOVE .\zig-out\bin\zig-spudde .\ladder_build\

"C:\Program Files\7-Zip\7z.exe" a -tzip ".\ladder_build.zip" ".\ladder_build\*"
