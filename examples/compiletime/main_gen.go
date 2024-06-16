package main

import (
	"io"

	"github.com/yueleshia/cmdtree/util"
)

type CLI struct{
	I [0]byte
	Validate CLIValidate
	ValidateStdin CLIValidateStdin
	Serve CLIServe
	Is_help bool
	Log_level string
}
func (_ *CLI) Help(writer io.Writer, program_name string) {
	data[""].Print_help(writer, program_name)
}
func (_ *CLI) Eat_options(cli interface{}, args *[]string) (string, error) {
	return data[""].Eat_options(cli, args)
}


type CLIValidateStdin struct{
	I [0]byte
}
func (_ *CLIValidateStdin) Help(writer io.Writer, program_name string) {
	data["enact"].Print_help(writer, program_name)
}
func (_ *CLIValidateStdin) Eat_options(cli interface{}, args *[]string) (string, error) {
	return data["enact"].Eat_options(cli, args)
}


type CLIServe struct{
	I [0]byte
	Port string
}
func (_ *CLIServe) Help(writer io.Writer, program_name string) {
	data["serve"].Print_help(writer, program_name)
}
func (_ *CLIServe) Eat_options(cli interface{}, args *[]string) (string, error) {
	return data["serve"].Eat_options(cli, args)
}


type CLIValidate struct{
	I [0]byte
}
func (_ *CLIValidate) Help(writer io.Writer, program_name string) {
	data["validate"].Print_help(writer, program_name)
}
func (_ *CLIValidate) Eat_options(cli interface{}, args *[]string) (string, error) {
	return data["validate"].Eat_options(cli, args)
}


var data = map[string]util.CmdTreeCommand{
	"": util.CmdTreeCommand{
		Name_path: "",
		Index_path: []int{},
		Option_indices: map[string]uint16{
			"--help": 0x4,
			"--log-level": 0x5,
			"-h": 0x4,
			"-l": 0x5,
		},
		Parameters: -1,
		Name: "thing",
		Description: "hello",
		Subcommands: []util.CmdTreeSubcommand{
			util.CmdTreeSubcommand{
				Name: "validate",
				Description: "a",
				Struct_name: "Validate",
				Name_path: "validate",
			},
			util.CmdTreeSubcommand{
				Name: "enact",
				Description: "c",
				Struct_name: "ValidateStdin",
				Name_path: "enact",
			},
			util.CmdTreeSubcommand{
				Name: "serve",
				Description: "d",
				Struct_name: "Serve",
				Name_path: "serve",
			},
		},
		Options: []util.CmdTreeOption{
			util.CmdTreeOption{
				Name: "-h, --help",
				Description: "Display this help message",
				Struct_name: "Is_help",
				Is_arg_required: false,
			},
			util.CmdTreeOption{
				Name: "-l, --log-level",
				Description: "Set the log level",
				Struct_name: "Log_level",
				Is_arg_required: true,
			},
		},
		Parent_options: []util.CmdTreeOption{},
		Go_name: "",
	},
	"enact": util.CmdTreeCommand{
		Name_path: "enact",
		Index_path: []int{
			2,
		},
		Option_indices: map[string]uint16{},
		Parameters: 1,
		Name: "enact",
		Description: "c",
		Subcommands: []util.CmdTreeSubcommand{},
		Options: []util.CmdTreeOption{},
		Parent_options: []util.CmdTreeOption{
			util.CmdTreeOption{
				Name: "-h, --help",
				Description: "Display this help message",
				Struct_name: "Is_help",
				Is_arg_required: false,
			},
			util.CmdTreeOption{
				Name: "-l, --log-level",
				Description: "Set the log level",
				Struct_name: "Log_level",
				Is_arg_required: true,
			},
		},
		Go_name: "ValidateStdin",
	},
	"serve": util.CmdTreeCommand{
		Name_path: "serve",
		Index_path: []int{
			3,
		},
		Option_indices: map[string]uint16{
			"--port": 0x1,
			"-p": 0x1,
		},
		Parameters: 0,
		Name: "serve",
		Description: "d",
		Subcommands: []util.CmdTreeSubcommand{},
		Options: []util.CmdTreeOption{
			util.CmdTreeOption{
				Name: "-p, --port",
				Description: "hello",
				Struct_name: "Port",
				Is_arg_required: true,
			},
		},
		Parent_options: []util.CmdTreeOption{
			util.CmdTreeOption{
				Name: "-h, --help",
				Description: "Display this help message",
				Struct_name: "Is_help",
				Is_arg_required: false,
			},
			util.CmdTreeOption{
				Name: "-l, --log-level",
				Description: "Set the log level",
				Struct_name: "Log_level",
				Is_arg_required: true,
			},
		},
		Go_name: "Serve",
	},
	"validate": util.CmdTreeCommand{
		Name_path: "validate",
		Index_path: []int{
			1,
		},
		Option_indices: map[string]uint16{},
		Parameters: 1,
		Name: "validate",
		Description: "a",
		Subcommands: []util.CmdTreeSubcommand{},
		Options: []util.CmdTreeOption{},
		Parent_options: []util.CmdTreeOption{
			util.CmdTreeOption{
				Name: "-h, --help",
				Description: "Display this help message",
				Struct_name: "Is_help",
				Is_arg_required: false,
			},
			util.CmdTreeOption{
				Name: "-l, --log-level",
				Description: "Set the log level",
				Struct_name: "Log_level",
				Is_arg_required: true,
			},
		},
		Go_name: "Validate",
	},
}
