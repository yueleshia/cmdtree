package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/yueleshia/cmdtree/util"
)

//run: go generate % && go build; ./compiletime serve --port 1000 && rm compiletime && git status --short

//go:generate go run ../../util/cmdtree/main.go --input-file main.go --type-name Main --var-name data --gen-prefix CLI --lib-import "github.com/yueleshia/cmdtree/util" main_gen.go
type Main struct {
	I [0]byte `name:"thing" description:"hello"`

	Validate      struct { I [0]byte `name:"validate"       params:"1" description:"a"` }
	ValidateStdin struct { I [0]byte `name:"enact"          params:"1" description:"c"` }
	Serve         struct {
		I    [0]byte `name:"serve"          params:"0" description:"d"`
		Port string  `flag:"-p,--port" description:"hello"`
	}

	Is_help   bool      `flag:"-h,--help"      description:"Display this help message"`
	Log_level string    `flag:"-l,--log-level" description:"Set the log level"`
}

// @TODO: work on Eat_options
var cmdtree = CLI{
	Is_help:   false,
	Log_level: "error",
}

func main() {
	program := filepath.Base(os.Args[0])
	args := os.Args[1:]
	var cmd string
	var arg_err error

	cmd, arg_err = cmdtree.Eat_options(&cmdtree, &args)
	if cmdtree.Is_help {
		// Even if no subcmd is provided detect help
		cmdtree.Help(util.LOG_STDERR.Writer(), program)
		os.Exit(0)
	}
	if arg_err != nil {
		fmt.Println(cmdtree)
		util.LOG_STDERR.Println(arg_err.Error())
		cmdtree.Help(util.LOG_STDERR.Writer(), program)
		os.Exit(1)
	}
	util.Set_log_level(cmdtree.Log_level)

	switch cmd {
	case "validate":
		_ = help_or_parse(program, &cmdtree.Validate, &args)
		fmt.Println(cmdtree)

	case "validate-stdin":
		_ = help_or_parse(program, &cmdtree.ValidateStdin, &args)
		fmt.Println(cmdtree)

	case "serve":
		_ = help_or_parse(program, &cmdtree.Serve, &args)
		fmt.Printf("Port is %s\n", cmdtree.Serve.Port)
		fmt.Println(cmdtree)

	default:
		cmdtree.Help(util.LOG_STDERR.Writer(), program)
	}
}

func help_or_parse(program string, cmd util.CmdTreeInterface, args *[]string) string {
	if cmdtree.Is_help {
		cmd.Help(util.LOG_STDERR.Writer(), program)
		os.Exit(0)
	}
	arg, err := cmd.Eat_options(&cmdtree, args)
	if err != nil {
		util.LOG_STDERR.Fatalln(err.Error())
	}
	return arg
}
