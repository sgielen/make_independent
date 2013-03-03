# make_independent

This is `make_independent.pl`, a script to make (parts of) an .app independent.
After this script has been run on an .app, it will have all listed .dylibs
shipped inside it with the paths fixed so that the dynamic loader will find
them. This means it will run on other Macs with the same OS X version, as long
as the application does not dynamically load .dylibs itself.

If the application does load dylibs itself, they can be copied into the .app,
then given as a relative path to this script. Again, it will recursively copy
all extra needed dylibs into the .app, so as long as the application loads
its dylib from the right spot, all its dependencies will be found too.

    Usage: ./make_independent.pl [-n] <path to .app> [relative path to file]

    Finds all .dylibs used by the given file (or, if not given, the executable
    of the .app), and copies them into the .app, updating any internal links.
    Works recursively on all copied .dylibs too. If the -n option is given, only
    outputs what it should have done, but does not actually change anything.

# License

See inside `make_independent.pl`.

# Authors

Version 1.0, written by Sjors Gielen.
