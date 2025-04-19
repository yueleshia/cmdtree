package cmdtree

import (
	"fmt"
	"log"
	"reflect"
	"strconv"
	"strings"
)

// Strips options

type Iter struct {
	root reflect.Value
	command reflect.Value
	is_double_dash bool
	optionless_args []string
	option_curr *StructField
	option_fulfilled_count int

	path strings.Builder
	options map[string][]StructField
	subcmds map[string][]StructField
}

func Init_iter[T any](ptr_to_cmd *T, init_capacity int) Iter {
	var ptr = reflect.ValueOf(ptr_to_cmd)
	//options, subcmds := parse_struct(ptr)

	ret := make([]string, 0, init_capacity + 1)
	ret = append(ret, "") // To make Done() easier

	options := make(map[string][]StructField)
	subcmds := make(map[string][]StructField)
	options[""], subcmds[""] = parse_struct(ptr)

	return Iter {
		root: ptr,
		command: ptr,
		is_double_dash: false,
		optionless_args: ret,
		options: options,
		subcmds: subcmds,
	}
}

func (iter *Iter) Parse(arg string) error {
	if iter.is_double_dash {
		iter.optionless_args = append(iter.optionless_args, arg)
		return nil
	} else if arg == "--" {
		iter.is_double_dash = true
		return nil
	} else if iter.option_curr != nil {
		x := *iter.option_curr

		field := iter.command.Elem().Field(x.index)

		switch x.param_count {
		case 0:
			field.Set(reflect.ValueOf(true))
		case 1:
			if x.is_required {
				field.Set(reflect.ValueOf(arg))
			} else {
				field.Set(reflect.ValueOf(arg))
			}

			switch x.kind {
			case reflect.Uint16:
				if s, err := strconv.ParseUint(arg, 10, 16); err != nil {

					return fmt.Errorf("%s %s requires a number between 0 and 65535", x.name, arg)
				} else if x.is_required {
					n := uint16(s)
					field.Set(reflect.ValueOf(n))
				} else {
					n := uint16(s)
					field.Set(reflect.ValueOf(&n))
				}
			case reflect.String:
				if x.is_required {
					field.Set(reflect.ValueOf(arg))
				} else {
					field.Set(reflect.ValueOf(&arg))
				}
			default:
				panic(fmt.Sprintf("@TODO: Add switch prong for %s", x.kind))
			}
			iter.option_curr = nil

		default:
			panic(fmt.Sprintf("@TODO: Not ready to support multiple arguments yet"))
			iter.option_fulfilled_count += 1
		}
	}

	for _, x := range iter.options[iter.path.String()] {
		if arg == x.name {
			iter.option_curr = &x
			iter.option_fulfilled_count = 0
		}

	}


	for _ , x := range iter.subcmds[iter.path.String()] {
		if arg == x.name {
			iter.optionless_args = append(iter.optionless_args, arg)

			iter.command = iter.command.Elem().Field(x.index)

			// @TODO: Rework this. We shouldn't fail here while parsing. We should fail on precompute.
			if _, err := iter.path.WriteString(arg); err != nil {
				return err
			}
			path := iter.path.String()
			iter.options[path], iter.subcmds[path] = parse_struct(iter.command)

			new_subcmd := reflect.New(iter.command.Type().Elem()) // Create a new &Command{}
			iter.command.Set(new_subcmd)
			break
		}
	}
	return nil
}


func (iter *Iter) Done() ([]string, error) {
	if iter.option_curr != nil {
		x := *iter.option_curr
		return nil, fmt.Errorf("%s is expecting another argument", x.name)
	}

	iter.path.Reset()
	state := iter.root.Elem()
	for _, arg := range iter.optionless_args {
		// We have a stealth extra arg and iter.optionless_args[0]
		if _, err := iter.path.WriteString(arg); err != nil {
			return nil, err
		}
		path := iter.path.String()

		for _, option := range iter.options[path] {
			if option.is_required && state.Field(option.index).IsNil() {
				return nil, fmt.Errorf("Error: %s is a required option", option.name)
			}
		}
		for _, subcmd := range iter.subcmds[path] {
			if arg == subcmd.name {
				state = state.Field(subcmd.index)
			}
		}
	}
	return iter.optionless_args[1:], nil
}

type StructField struct {
	name string
	index int
	kind reflect.Kind
	description string
	param_count int
	is_required bool
}

func parse_struct(cmd reflect.Value) ([]StructField, []StructField) {
	ty := cmd.Type().Elem()
	field_count := ty.NumField()

	options := make([]StructField, 0, field_count)
	subcmds := make([]StructField, 0, field_count)

	for i := 0; i < field_count; i += 1 {
		field := ty.Field(i)
		field_type := field.Type
		field_desc := field.Tag.Get("description")

		is_unsupported, is_required := false, false
		switch field_type.Kind() {
		case reflect.Pointer:
			is_unsupported, is_required, field_type = false, false, field_type.Elem()
		case reflect.Bool:
		case reflect.Uint16: fallthrough
		case reflect.String: is_required = true
		default: is_unsupported = true
		}

		name_convention := strings.ToLower(strings.ReplaceAll(field.Name, "_", "-"))
		switch field_type.Kind() {
		case reflect.Bool:
			options = append(options, StructField{
				index: i,
				name: "--" + name_convention,
				description: field_desc,
				kind: field_type.Kind(),
				param_count: 0,
				is_required: is_required,
			})
		case reflect.Uint16: fallthrough
		case reflect.String:
			options = append(options, StructField{
				index: i,
				name: "--" + name_convention,
				description: field_desc,
				kind: field_type.Kind(),
				param_count: 1,
				is_required: is_required,
			})
		case reflect.Struct:
			subcmds = append(subcmds, StructField{
				index: i,
				name: name_convention,
				description: field_desc,
				kind: field_type.Kind(),
				param_count: 0,
				is_required: false,
			})
		default:
			is_unsupported = true
		}

		if is_unsupported {
			panic(fmt.Sprintf("%v.%s is a type %q which is not supported by our CLI parser, add a new switch prong for it.", ty, field.Name, field_type.Name()))
		}
	}

	return options, subcmds
}

// Only can really return out of memory

// Saves on re-parsing the go structure
func (iter *Iter) Help(logger *log.Logger, app_name string) (string, error) {
	_ = iter
	path := iter.path.String()
	// We added +1 elements in internal optionless_args
	return Help_base(logger, iter.options[path], iter.subcmds[path], app_name, iter.optionless_args[1:])
}

// Parses the go struct `cmd` and prints its help message
func Help(logger *log.Logger, cmd reflect.Value, app_name string, optionless_args []string) (string, error) {
	options, subcmds := parse_struct(cmd)
	return Help_base(logger, options, subcmds, app_name, optionless_args)
}

func Help_base(logger *log.Logger, options, subcmds []StructField, app_name string, optionless_args []string) (string, error) {
	// We will have two columns, the option/subcmd and its description
	col_width := len("--help")
	option_optional_count := 0
	{
		for _, x := range subcmds {
			if len(x.name) > col_width {
				col_width = len(x.name)
			}
		}
		for _, x := range options {
			if !x.is_required {
				option_optional_count += 1
			}

			l := len(x.name)
			switch x.param_count {
			case 0: l += 0
			case 1: l += len(" VALUE")
			default: panic("@TODO: Options requiring multiple parameters is unsupported")
			}
			if l > col_width {
				col_width = l
			}
		}
	}
	var whitespace = strings.Repeat(" ", col_width + 4) // 4 spaces of padding between the two columns


	var builder strings.Builder
	// Helpers
	add_row := func (x StructField) error {
		if _, err := builder.WriteString("  "); err != nil { return err }

		width := len(x.name)
		switch x.param_count {
		case 0: if _, err := builder.WriteString(x.name); err != nil { return err }
		case 1:
			if _, err := builder.WriteString(x.name); err != nil { return err }
			if _, err := builder.WriteString(" VALUE"); err != nil { return err }
			width += len(" VALUE")
		default:
			panic("@TODO: Options requiring multiple parameters is unsupported")
		}
		if _, err := builder.WriteString(whitespace[0:len(whitespace) - width]); err != nil { return err }
		if _, err := builder.WriteString(x.description); err != nil { return err }
		if _, err := builder.WriteString("\n"); err != nil { return err }
		return nil
	}

	// Usage
	if _, err := builder.WriteString("Usage: "); err != nil { return "", err }
	if _, err := builder.WriteString(app_name); err != nil { return "", err }
	for _, s := range optionless_args {
		if _, err := builder.WriteString(" "); err != nil { return "", err }
		if _, err := builder.WriteString(s); err != nil { return "", err }
	}
	for _, x := range options {
		_ = x
		//if x.is_required {
		//	if _, err := builder.WriteString(" "); err != nil { return "", err }
		//	if _, err := builder.WriteString(x.name); err != nil { return "", err }
		//	switch x.param_count {
		//	case 0:
		//	case 1:
		//		if _, err := builder.WriteString(" <VALUE>"); err != nil { return "", err }
		//	default:
		//		panic("@TODO: Options requiring multiple parameters is unsupported")
		//	}
		//}
	}
	if len(subcmds) > 0 {
		if _, err := builder.WriteString(" [command]"); err != nil { return "", err }
	}
	if _, err := builder.WriteString(" [option]"); err != nil { return "", err }
	if _, err := builder.WriteString("\n"); err != nil { return "", err }

	// Subcommands
	if len(subcmds) > 0 {
		if _, err := builder.WriteString("\nCommands:\n\n"); err != nil { return "", err }
		for _, x := range subcmds {
			add_row(x)
		}
	}

	// Options
	if len(options) > 0 {
		if _, err := builder.WriteString("\nOptions:\n\n"); err != nil { return "", err }
		for _, x := range options {
			add_row(x)
		}
	}

	return builder.String(), nil
}
