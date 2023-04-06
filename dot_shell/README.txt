The idea of this directory is to share common configuration between different
shells.  Specifically, items in this directory are meant to be able to be 
sourced by the configuration files used by bash and zsh.  

As such, functionality and idioms that bash or zsh specific are to be avoided
in this files.  However there is a lot of overlap because of their common
Bource/sh and POSIX shell roots that this is possible to a large degree.  

For example, while both bash and zsh have specific and divergent flags that can
be used with the export keywords you probably don't use them very often and
likely don't have to if you do use them. So, by dropping the shell specific
flags and just using export environment variables can be stood up for both
shells.

