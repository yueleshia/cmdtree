package util

import (
  "fmt"      // for errors
  "io"       // for help func
  "reflect"
  "strconv"  // for `params:` struct tag on I field
  "strings"  // for path joining
)

const (
	// Match type of CmdtreeCommand.Parameters
	arg_count_nil int32 = -1
	arg_count_etc int32 = -2
)

type CmdTreeInterface interface {
	Help(io.Writer, string)
	Eat_options(interface{}, *[]string) (string, error)
}

type CmdTreeData map[string]CmdTreeCommand
type CmdTreeCommand struct {
	Name_path      string
	Index_path     []int
	Option_indices map[string]uint16
	Parameters     int32

	// Help-only
	Name           string
	Description    string
	Subcommands    []CmdTreeSubcommand
	Options        []CmdTreeOption
	Parent_options []CmdTreeOption

	// Generate-only
	Go_name        string
}
// Stripped down verison of CmdTreeCommand.
// The other fields of CmdTree are unnecessary because we call Parse_command
// recursively, and we only care about the immediate subcommands at each step.
type CmdTreeSubcommand struct {
	Name        string
	Description string
	Struct_name string
	Name_path   string
}
type CmdTreeOption struct {
	Name            string
	Description     string
	Struct_name     string
	Is_arg_required bool
}

// If you do not want to use the generator, this is the start point
func Parse_cmdtree(ty reflect.Type) (CmdTreeData, error) {
	data := make(CmdTreeData)
	err := parse_recursive(data, []string{ty.Name()}, []int{}, ty, ty)
	return data, err
}

// Commands can be embedded within other commands, so we must parse recursively
// Expecting path to start with [base_ty.Name].
func parse_recursive(data map[string]CmdTreeCommand, path []string, index_path []int, base_ty, ty reflect.Type) error {
	cmd, err := parse_command(path, index_path, base_ty, ty)
	if err != nil {
		return err
	}
	data[cmd.Name_path] = cmd

	for i := 0; i < ty.NumField(); i += 1 {
		field := ty.Field(i)
		if reflect.Struct == field.Type.Kind() {
			err := parse_recursive(data, append(path, field.Name), append(index_path, i), base_ty, field.Type)
			if err != nil {
				return err
			}
		}
	}
	return nil
}

////////////////////////////////////////////////////////////////////////////////
// Parse into backend -- reusable both by the go:generate and the runtime flow

func parse_command(struct_path []string, index_path []int, base_ty reflect.Type, ty reflect.Type) (CmdTreeCommand, error) {
	var uninit CmdTreeCommand

	struct_name := strings.Join(struct_path, ".")
	if base_ty.Kind() != reflect.Struct {
		return uninit, fmt.Errorf("You provided %q as the Base type in `Parse_command[Base,](..)` but it is not a struct", base_ty.Name())
	}
	if ty.Kind() != reflect.Struct {
		return uninit, fmt.Errorf("You provided %q as the Base type in `Parse_command[Base,](..)` but it is not a struct", ty.Name())
	}


	parent_option_count, err := count_parent_options(struct_path, base_ty)
	if err != nil {
		return uninit, err
	}
	var subcommand_count uint16
	var option_count uint16
	for i := 0; i < ty.NumField(); i += 1 {
		field := ty.Field(i)
		switch field.Type.Kind() {
		case reflect.String:
			fallthrough
		case reflect.Bool:
			option_count += 1
		case reflect.Struct:
			subcommand_count += 1
		}
	}
	data := CmdTreeCommand{
		Go_name:        struct_path[len(struct_path) - 1],
		Name_path:      "",
		Index_path:     index_path,
		Name:           "",
		Description:    "",
		Subcommands:    make([]CmdTreeSubcommand, subcommand_count),
		Option_indices: make(map[string]uint16), // Need size of flag split
		Options:        make([]CmdTreeOption, option_count),
		Parent_options: make([]CmdTreeOption, parent_option_count),
		Parameters:     arg_count_nil,
	}
	if err := data.set_name_path(struct_path, base_ty); err != nil {
		return uninit, err
	}
	if err := data.set_parent_options(struct_path, base_ty); err != nil {
		return uninit, err
	}

	// Parse data.Subcommands and direct data.Options
	var option_index uint16 = 0
	var subcommand_index uint16 = 0
	for i := uint16(0); int(i) < ty.NumField(); i += 1 {
		field := ty.Field(int(i))

		if field.Name == "I" {
			data.Name = field.Tag.Get("name")
			data.Description = field.Tag.Get("description")
			if arg_count, ok := field.Tag.Lookup("params"); ok {
				u, err := strconv.ParseUint(arg_count, 10, 16)
				if err != nil {
					return uninit, fmt.Errorf("On the subcommand %q, the field \"I\" should be a number", struct_name, field.Name)
				}
				data.Parameters = int32(u)
			}
		} else if tag, ok := field.Tag.Lookup("flag"); ok {
			option, err := parse_option(struct_name, field)
			if err != nil {
				return uninit, err
			}
			for _, name := range strings.Split(tag, ",") {
				data.Option_indices[name] = i
			}
			data.Options[option_index] = option
			option_index += 1
		} else {
			if field.Type.Kind() != reflect.Struct {
				return uninit, fmt.Errorf("The subcommand %q should be an embeded struct", struct_name)
			}
			subcmd := field.Type
			subcmd_info, ok := subcmd.FieldByName("I")
			if !ok {
				return uninit, fmt.Errorf("The subcommand %q requires the field \"I\" to exist for struct tagging", struct_name)
			}

			name, ok := subcmd_info.Tag.Lookup("name")
			if !ok {
				return uninit, fmt.Errorf("On the subcommand %q, the field \"I\" does not have the struct tag `name:`", struct_name)
			}
			var name_path_subcommand string
			if data.Name_path == "" {
				name_path_subcommand = name
			} else {
				name_path_subcommand = strings.Join([]string{data.Name_path, name}, " ")
			}
			data.Subcommands[subcommand_index] = CmdTreeSubcommand{name, subcmd_info.Tag.Get("description"), field.Name, name_path_subcommand}
			subcommand_index += 1
		}
	}



	//if len(data.Subcommands) <= 0 {
	//	if data.Parameters == arg_count_nil {
	//		fmt.Println(data.Parameters)
	//		return uninit, fmt.Errorf("Please specify the number of parameters for terminal commands (structs with no subcommands).\nTag %s.i with `params:\"<arg_count>\"`", struct_name)
	//	}
	//} else {
	//	if data.Parameters != arg_count_nil {
	//		return uninit, fmt.Errorf("Parent commands (has subcommands) cannot have params.\nTag %s.i with `params:\"<arg_count>\"`", struct_name)
	//	}
	//}
	return data, nil
}

// Separated out its own function because we use this twice
func parse_option(struct_name string, field reflect.StructField) (CmdTreeOption, error) {
	var uninit CmdTreeOption
	flag := field.Tag.Get("flag")

	if !field.IsExported() {
		return uninit, fmt.Errorf("The field %q is not public, capitalize the first letter to export.", field.Name)
	}

	if flag == "" {
		return uninit, fmt.Errorf("%s.%s is tagged an empty `flag:\"\"`", struct_name, field.Name)
	}

	is_arg_required := false
	switch field.Type.Kind() {
	case reflect.Bool:
	case reflect.String:
		is_arg_required = true
	default:
		return uninit, fmt.Errorf("The option %s.%s is not a supported type: bool, string, or io.Reader", struct_name, field.Name)
	}

	name := strings.Join(strings.Split(flag, ","), ", ")
	description := field.Tag.Get("description")
	return CmdTreeOption{name, description, field.Name, is_arg_required}, nil

}

////////////////////////////////////////////////////////////////////////////////
// Helpers
func count_parent_options(struct_path []string, walk reflect.Type) (uint16, error) {
	var count uint16 = 0
	for i, component := range struct_path[1:] {
		// Add parent options before we move `walk` into struct_path[i]
		for i := 0; i < walk.NumField(); i += 1 {
			field := walk.Field(i)
			switch field.Type.Kind() {
			case reflect.String:
				fallthrough
			case reflect.Bool:
				count += 1
				if _, ok := field.Tag.Lookup("flag"); !ok {
					panic("@TODO")
				}
			case reflect.Struct:
				fallthrough
			default:
				if _, ok := field.Tag.Lookup("flag"); ok {
					panic("@TODO")
				}
			}
		}

		if f, ok := walk.FieldByName(component); ok {
			walk = f.Type
		} else {
			panic(fmt.Sprintf("The field %q does not exist in %q\n", strings.Join(struct_path[1:i], "_")))
		}
	}
	//fmt.Println(walk.Field(0).Index)
	return count, nil
}
func (data *CmdTreeCommand) set_parent_options(struct_path []string, walk reflect.Type) error {
	var option_index uint16 = 0
	for i, component := range struct_path[1:] {
		// Add parent options before we move `walk` into struct_path[i]
		for i := 0; i < walk.NumField(); i += 1 {
			field := walk.Field(i)
			if _, ok := field.Tag.Lookup("flag"); ok {
				option, err := parse_option(walk.Name(), field)
				if err != nil {
					return err
				}
				data.Parent_options[option_index] = option
				option_index += 1
			}
		}

		if f, ok := walk.FieldByName(component); ok {
			walk = f.Type
		} else {
			panic(fmt.Sprintf("The field %q does not exist in %q\n", strings.Join(struct_path[1:i], "_")))
		}
	}
	Assert_eq(uint16(len(data.Parent_options)), option_index, "The checks of count_parent_options() are inconsistent with the checks of parse_option()")
	// @TODO: check that there are no overlapping parent options
	return nil
}
func (data *CmdTreeCommand) set_name_path(struct_path []string, walk reflect.Type) error {
	to_join := make([]string, len(struct_path[1:]))
	for i, component := range struct_path[1:] {
		if f, ok := walk.FieldByName(component); ok {
			walk = f.Type
		} else {
			panic(fmt.Sprintf("The field %q does not exist in %q\n", strings.Join(struct_path[1:i], "_")))
		}

		// Set name of the subcommand
		if info_field, ok := walk.FieldByName("I"); ok {
			if name, ok := info_field.Tag.Lookup("name"); ok {
				to_join[i] = name
			} else {
				return fmt.Errorf("Commands embedded as subcommands require names. The type \"%s.I\" has no struct tag `name`.\n", walk.Name())
			}
		} else {
			return fmt.Errorf("Penzai requires the field \"%s.I\" to exist for name and description struct tagging.\n", walk.Name())
		}
	}
	data.Name_path = strings.Join(to_join, " ")
	return nil
}



////////////////////////////////////////////////////////////////////////////////
// Argument Parsing

// Panic when something should have been caught by Parse(), i.e. errors with
// the schema or tagging of T.
// Errors should be reserved for input errors
func (data CmdTreeCommand) Eat_options(tree interface{}, args *[]string) (string, error) {
	value := reflect.ValueOf(tree).Elem()
	j := int32(0)
	length := len(*args)
	for i := 0; i < length; i += 1 {
		curr := (*args)[i]

		if field_index, ok := data.Option_indices[curr]; ok {
			field := value.FieldByIndex(data.Index_path).Field(int(field_index))
			//field := value.FieldByIndex(data.Index_path).Field(int(field_index))

			switch field.Kind() {
			case reflect.Bool:
				field.SetBool(true)
			case reflect.String:
				if (i + 1) >= length {
					return "", fmt.Errorf("No more arguments. %s is expecting an argument", curr)
				} else {
					field.SetString((*args)[i + 1])
					i += 1
				}
			default:
				panic(fmt.Sprintf("This should have been caught while calling `Parse_command`.\nThe option %q refers to the %d-th field %q", curr, field_index, field.Type().Name()))
			}
		} else {
			(*args)[j] = (*args)[i]
			j += 1
		}
	}
	*args = (*args)[0:j]
	
	if len(data.Subcommands) == 0 {
		if j != data.Parameters {
			return "", fmt.Errorf("You did not provide the correct number of parameters.\n  expected: %d\n  recieved: %d\n[%s]", data.Parameters, j, strings.Join(*args, ", "))
		} else {
			return "", nil
		}
	} else if j <= 0 {
		return "", fmt.Errorf("You did not provide a subcommand")
	} else {
		for _, subcmd := range data.Subcommands {
			if (*args)[0] == subcmd.Name {
				first := (*args)[0]
				*args = (*args)[1:]
				return first, nil
			}
		}
		return "", fmt.Errorf("%q is not a valid subcommand", (*args)[0])
	}
}



////////////////////////////////////////////////////////////////////////////////
// Help
func (data CmdTreeCommand) Print_help(out io.Writer, name string) {
	fmt.Fprintf(out, "USAGE\n")
	fmt.Fprintf(out, "  %s", name)
	if len(data.Name_path) != 0 {
		fmt.Fprintf(out, " %s", data.Name_path)
	}
	if len(data.Options) > 0 {
		fmt.Fprintf(out, " [OPTIONS]")
	}
	if len(data.Subcommands) > 0 {
		fmt.Fprintf(out, " <SUBCOMMAND>")
	}
	switch data.Parameters {
	case arg_count_etc:
		fmt.Fprintf(out, " [<arg>]...")
	default:
		for i := int32(0); i < data.Parameters; i += 1 {
			fmt.Fprintf(out, " <arg>")
		}
	}
	fmt.Fprintf(out, "\n")

	if len(data.Description) > 0 {
		fmt.Fprintf(out, "\nDESCRIPTION\n  %s\n", data.Description)
	}

	if len(data.Subcommands) > 0 {
	fmt.Fprintf(out, "\nSUBCOMMANDS\n")
		max_len := 0
		for _, subcmd := range data.Subcommands {
			length := len(subcmd.Name)
			if length > max_len {
				max_len = length
			}
		}
		// Left align with padding of max_len
		format := strings.Join([]string{"  %-", strconv.Itoa(max_len), "s"}, "")

		for _, subcmd := range data.Subcommands {
			fmt.Fprintf(out, format, subcmd.Name)
			fmt.Fprintf(out, "  %s\n", subcmd.Description)
		}
	}


	print_options := func (out io.Writer, options []CmdTreeOption) {
		any_require_arg := false
		max_len := 0
		for _, option := range options {
			length := len(option.Name)
			any_require_arg =  any_require_arg || option.Is_arg_required
			if length > max_len {
				max_len = length
			}
		}
		// Left align with padding of max_len
		format := strings.Join([]string{"  %-", strconv.Itoa(max_len), "s"}, "")


		for _, option := range options {
			fmt.Fprintf(out, format, option.Name)
			fmt.Fprintf(out, "  %s\n", option.Description)
		}
	}

	if len(data.Options) > 0 {
		fmt.Fprintf(out, "\nOPTIONS\n")
		print_options(out, data.Options)
	}
	if len(data.Parent_options) > 0 {
		fmt.Fprintf(out, "\nPARENT OPTIONS\n")
		print_options(out, data.Parent_options)
	}
}
