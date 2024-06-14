# Package

version       = "0.1.0"
author        = "SirOlaf"
description   = "Experimental chat community server with multiple identities out of the box."
license       = "MIT"
srcDir        = "src"
installExt    = @["nim"]
bin           = @["server"]


# Dependencies

requires "nim >= 2.1.1"

requires "happyx >= 3.11.0"
