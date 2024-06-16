package main

import (
	"fmt"
	"reflect"
	"os"
	"path/filepath"

	"github.com/yueleshia/cmdtree/util"
)

//run: go build; ./runtime serve --port 1000 && rm runtime

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

var data = util.Must(util.Parse_cmdtree(reflect.TypeFor[Main]()))

var cmdtree = Main{
	Is_help:   false,
	Log_level: "error",
}

func main() {
	program := filepath.Base(os.Args[0])
	args := os.Args[1:]
	var cmd string
	var arg_err error

	cmd, arg_err = data[""].Eat_options(&cmdtree, &args)
	if cmdtree.Is_help {
		data[""].Print_help(os.Stderr, program)
		os.Exit(0)
	}
	if arg_err != nil {
		util.LOG_STDERR.Println(arg_err.Error())
		data[""].Print_help(util.LOG_STDERR.Writer(), program)
		os.Exit(1)
	}
	util.Set_log_level(cmdtree.Log_level)
	fmt.Println("hello")

	switch cmd {
	case "validate":
		_ = help_or_parse(program, "validate", &args)
		fmt.Println(cmdtree)

	case "validate-stdin":
		_ = help_or_parse(program, "validate-stdin", &args)
		fmt.Println(cmdtree)

	case "serve":
		_ = help_or_parse(program, "serve", &args)
		fmt.Printf("Port is %s\n", cmdtree.Serve.Port)
		fmt.Println(cmdtree)

	default:
		data[""].Print_help(util.LOG_STDERR.Writer(), program)
	}
}

func help_or_parse(program string, subcmd_path string, args *[]string) string {
	if cmdtree.Is_help {
		data[subcmd_path].Print_help(os.Stderr, program)
		os.Exit(0)
	}
	arg, err := data[subcmd_path].Eat_options(&cmdtree, args)
	if err != nil {
		util.LOG_STDERR.Fatalln(err.Error())
	}
	return arg
}
