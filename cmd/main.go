package main

import (
	"log"
	"fmt"
	"reflect"
	"os"

	"github.com/yueleshia/cmdtree/cmdtree"
)

var ARGS = struct {
	Hello     *CmdNoArgs `description:"Says hello"`
	Print     *CmdPrint  `description:"Print a message"`
	Version   *CmdNoArgs `description:"Display the version of this program"`
	Dry_run   bool       `description:"Only prints what this program is doing"`
	Help      bool       `description:"Display this help menu"`
	Log_level *string    `description:"Possible values: debug, trace, warn, error"`
}{}

type CmdNoArgs struct {}
type CmdPrint struct {
	Help    bool   `description:"Display this help menu"`
	Message string `description:"Message to print"`
}

//run: go run % print --message "Hello world"
func main() {
	var optionless_args []string
	iter := cmdtree.Init_iter(&ARGS, len(os.Args[1:]))
	{
		for _, arg := range os.Args[1:] {
			if err := iter.Parse(arg); err != nil {
				ERROR_LOG.Fatalf("%s\n", err.Error())
			}
		}
		if x, err := iter.Done(); err != nil {
				ERROR_LOG.Fatalf("%s\n", err.Error())
		} else {
			optionless_args = x
		}
	}

	if len(optionless_args) == 0 {
		STDERR_LOG.Print(Must(cmdtree.Help(ERROR_LOG, reflect.ValueOf(&ARGS), PROJECT_NAME, optionless_args)))
		return
	}


	switch optionless_args[0] {
	case "print":
		if ARGS.Print.Help {
			STDERR_LOG.Print(Must(iter.Help(ERROR_LOG, PROJECT_NAME)))
		}
		fmt.Println(ARGS.Print.Message)

	case "version":
		fmt.Println(VERSION)
	default:
		STDERR_LOG.Fatalf("@TODO: %s has to still be implemented", optionless_args[0])
		os.Exit(1)
	}
}

var PROJECT_NAME = os.Args[0]
var VERSION = "1.0"

func Must[T any](x T, err error) T {
	if err != nil {
		STDERR_LOG.Fatalln(err.Error())
	}
	return x
}

func Must2[T, U any](x T, y U, err error) (T, U) {
	if err != nil {
		STDERR_LOG.Fatalln(err.Error())
	}
	return x, y
}

var STDERR_LOG = log.New(os.Stderr, "", 0)
var ERROR_LOG  = log.New(os.Stderr, "", 0)
