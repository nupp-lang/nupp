-- Lua twin of catalog-process-exit.nupp.
io.write("before exit\n")
print("printed", 1)
os.exit(3)
print("never")

return 0
