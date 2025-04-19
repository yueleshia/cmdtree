# Introduction

This is a repo for my various attempts at making a command line parsing library.

In different branches you'll language specific implementations.
CLI argument parsing generally have too many features, and currently programming culture generally has too many dependencies in generally.
Hopeuflly implementations are easy to comprehend and vendor into a project.


# Problems

There are several standards, some of which compete with each other.

* `terraform -version` as popularized by go (single dashes)
* `mysql -hwww.example.com -uadmin` short form that allow arguments in single
* `mysql --host example.com -u admin` specifying arguments with space
* `mysql --host=example.com -u=admin` specifying arguments with equal
* `grep -sv --regexp " *"`  combining short form arguments
* `?? +option` relatively rare, but turns off an option
* `xargs -- echo '{}'` disable argument parsing after the double dash

# My solution

Generally, these solutions will only aim to support the following features

* Iterator API so that you can do your own intergrations if you so wish
* `--`
* `command subcommands`
* `-f --flag` as multiple aliases for a single command
* Required vs non-required options
* Range validation for integers?
