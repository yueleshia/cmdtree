package main

import (
	"cmp"
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"strings"
	"reflect"
	"slices"
	"sort"
	"text/template"
	"os"

	"github.com/yueleshia/cmdtree/util"
)

//type Main struct {
//	I [0]byte `name:"thing" description:"hello"`
//
//	CmdValidate1 struct { I [0]byte `name:"validate"       params:"1" description:"a"` }
//	CmdValidate2 struct { I [0]byte `name:"validate-stdin" params:"0" description:"b"` }
//	CmdEnact1    struct { I [0]byte `name:"enact"          params:"1" description:"c"` }
//	CmdEnact2    struct { I [0]byte `name:"enact-stdin"    params:"0" description:"d"` }
//	CmdServe     struct { I [0]byte `name:"serve"          params:"0" description:"d"` }
//	Test         struct {
//		I    [0]byte `name:"test"          params:"0" description:"d"`
//		Port string  `flag:"-p,--port" description:"hello"`
//	}
//	Test2        struct {
//		I    [0]byte `name:"test2"          params:"0" description:"d"`
//		Port string  `flag:"-p,--port" description:"world"`
//		Hello struct { I [0]byte `name:"asdf" params:"0" description:"e"` }
//	}
//
//	Is_help   bool      `flag:"-h,--help"      description:"Display this help message"`
//	Log_level string    `flag:"-l,--log-level" description:"Set the log level"`
//}

type Main struct {
	I [0]byte `name:"" params:"1" description:"Generates the types of Use with go:generate to  of parsing them at runtime"`
	Input_file string `flag:"--input-file" description:"Path of file to parse"`
	Var_name   string `flag:"--var-name"   description:"Ident of the variable to hold the struct metadata"`
	Type_name  string `flag:"--type-name"  description:"Ident of the type to find in --input-file <file>"`
	Gen_prefix string `flag:"--gen-prefix" description:"The prefix to use for the generated idents"`
	Lib_import string `flag:"--lib-import" description:"The module path for cmdtree that is imported in the generated file"`
}

var cli Main
var cmdtree_data = util.Must(util.Parse_cmdtree(reflect.TypeFor[Main]()))

// @TODO: sort options
// @TODO: required options

//run: go run *.go -- --input-file main.go --type-name Main --var-name cli --gen-prefix CLI --lib-import "github.com/shimmeril/ci-enact/util/cmdtree" /dev/stdout
func main() {
	args := make([]string, len(os.Args))
	// Ignore '--', we will probably use this with `go run` and need it for that
	{
		i := 0
		for _, arg := range os.Args[1:] {
			if arg != "--" {
				args[i] = arg
				i += 1
			}
		}
		args = args[0:i]
	}
	if _, err := cmdtree_data[""].Eat_options(&cli, &args); err != nil {
		fmt.Fprintln(os.Stderr, err.Error())
		os.Exit(1)
	}
	output_file := args[0]

	file_set := token.NewFileSet()
	file_ast := util.Unwrap(parser.ParseFile(file_set, cli.Input_file, nil, 0))
	struct_type := util.Unwrap(filter_for_top_level_ident(file_ast, cli.Type_name))
	ty := util.Unwrap(convert_ast_to_reflect_type(*struct_type))

	data, err := util.Parse_cmdtree(ty)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s\n", err)
		os.Exit(1)
	}

	fh, err := os.Create(output_file)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Could not open %q. %s", output_file, err)
		os.Exit(1)
	}

	var pkg string
	{
		components := strings.Split(cli.Lib_import, "/")
		pkg = components[len(components) - 1]
	}
	template_input := struct{
		Prefix           string
		Data             util.CmdTreeData
		Data_name        string
		Package          string
		Import           string
		Replace_pkg      string
	}{cli.Gen_prefix, data, cli.Var_name, file_ast.Name.Name, cli.Lib_import, pkg}

	if err := t.Execute(fh, template_input); err != nil {
		fmt.Fprintf(os.Stderr, "%s\n", err)
		os.Exit(1)
	}
}

// Mostly so that `go fmt` does not mangle the formatting
func line(input ...string) string {
	return strings.Join(input, "")
}

var funcs = template.FuncMap {
	"format_type": format_type,
	"format_and_replace_pkg_path": func (pkg string, data util.CmdTreeData) string {
		var ret strings.Builder
		format_and_replace_pkg_path(pkg, reflect.ValueOf(data), 0, &ret)
		return ret.String()
	},
	// @TODO: might not need this if text/template `range $key, $value := <map>`
	//        always goes in a static order. We want the same order to reduce
	//        git churn
	"sorted_keys": func (data util.CmdTreeData) []string {
		keys := make([]string, len(data))
		i := 0
		for k, _ := range data {
			keys[i] = k
		}
		sort.Sort(sort.StringSlice(keys))
		return keys
	},
}

var t = util.Must(template.New("Generate").Funcs(funcs).Parse(`
{{- $prefix      := .Prefix      -}}
{{- $data        := .Data        -}}
{{- $data_name   := .Data_name   -}}
{{- $pkg         := .Package     -}}
{{- $import      := .Import      -}}
{{- $replace_pkg := .Replace_pkg -}}
package {{ $pkg }}

import (
	"io"

	{{ $import | printf "%#v" }}
)

{{- range $key, $cmdtree := $data }}

type {{$prefix}}{{ format_type $cmdtree $cmdtree.Go_name $prefix }}
func (_ *{{$prefix}}{{$cmdtree.Go_name}}) Help(writer io.Writer, program_name string) {
	{{$data_name}}[{{ $cmdtree.Name_path | printf "%q" }}].Print_help(writer, program_name)
}
func (_ *{{$prefix}}{{$cmdtree.Go_name}}) Eat_options(cli interface{}, args *[]string) (string, error) {
	return {{$data_name}}[{{ $cmdtree.Name_path | printf "%q" }}].Eat_options(cli, args)
}
{{ end }}

var {{$data_name}} = {{ $data | format_and_replace_pkg_path $replace_pkg }}
`))

//{{- range $key, $cmdtree := $data }}
//{{- range $key := sorted_keys $data }}
//{{- $cmdtree := index $data $key -}}


////////////////////////////////////////////////////////////////////////////////
// Text output

// Hand craft the output of format_type so that go fmt does not reformat this
func format_type(cmd util.CmdTreeCommand, go_name string, prefix string) string {
	var subcommands string
	{
		a := make([]string, len(cmd.Subcommands))
		i := 0
		for _, subcommand := range cmd.Subcommands {
			a[i] = strings.Join([]string {
				"\n\t",
				subcommand.Struct_name,
				" ",
				prefix,
				subcommand.Struct_name,
			}, "")
			i += 1
		}
		subcommands = strings.Join(a, "")
	}
	var options string
	{
		a := make([]string, len(cmd.Options))
		for i, option := range cmd.Options {
			a[i] = strings.Join([]string {
				"\n\t",
				option.Struct_name,
				func () string {
					if option.Is_arg_required {
						return " string"
					} else {
						return " bool"
					}
				}(),
			}, "")
		}
		options = strings.Join(a, "")
	}

	return strings.Join([]string{
		go_name,
		" struct{\n\tI [0]byte",
		subcommands,
		options,
		"\n}",
	}, "")
}


// Same as `sprintf("%#v")` but replaces all package paths with `pkg`
func format_and_replace_pkg_path(pkg string, s reflect.Value, tab_indent uint16, ret *strings.Builder) {
	indent := strings.Repeat("\t", int(tab_indent))
	ty := s.Type()
	//val := reflect.ValueOf(s)

	switch ty.Kind() {
	case reflect.Struct:
		var p string
		if "" != ty.PkgPath() {
			p = pkg + "."
		} else {
			p = ""
		}
		ret.WriteString(line(p, ty.Name(), "{"))
		for i := 0; i < ty.NumField(); i += 1 {
			ret.WriteString(line("\n\t", indent, fmt.Sprintf("%s", ty.Field(i).Name), ": "))
			format_and_replace_pkg_path(pkg, s.Field(i), tab_indent + 1, ret)
			ret.WriteString(",")
		}
		if ty.NumField() > 0 {
			ret.WriteString(line("\n", indent, "}"))
		} else {
			ret.WriteString("}")
		}
	case reflect.Map:
		var p string
		if "" != ty.Elem().PkgPath() {
			p = pkg + "."
		} else {
			p = ""
		}
		ret.WriteString(line("map[", ty.Key().Name(), "]", p, ty.Elem().Name(), "{"))

		type entry struct {
			field string
			value reflect.Value
		}
		entries := make([]entry, s.Len())
		iter := s.MapRange()
		i := 0
		for iter.Next() {
			entries[i] = entry{iter.Key().String(), iter.Value()}
			i += 1
		}
		slices.SortFunc(entries, func (a, b entry) int {
			return cmp.Compare(a.field, b.field)
		})

		for _, entry := range entries {
			ret.WriteString(line("\n\t", indent, fmt.Sprintf("%#v", entry.field), ": "))
			format_and_replace_pkg_path(pkg, entry.value, tab_indent + 1, ret)
			ret.WriteString(",")
		}

		if len(entries) > 0 {
			ret.WriteString(line("\n", indent, "}"))
		} else {
			ret.WriteString("}")
		}

	case reflect.Array:
		panic("@TODO")
	case reflect.Slice:
		var p string
		if "" != ty.Elem().PkgPath() {
			p = pkg + "."
		} else {
			p = ""
		}
		ret.WriteString(line("[]", p, ty.Elem().Name(), "{"))
		for i := 0; i < s.Len(); i += 1 {
			ret.WriteString("\n\t")
			ret.WriteString(indent)
			format_and_replace_pkg_path(pkg, s.Index(i), tab_indent + 1, ret)
			ret.WriteString(",")
		}
		if s.Len() > 0 {
			ret.WriteString(line("\n", indent, "}"))
		} else {
			ret.WriteString("}")
		}
	case reflect.Chan:
		panic("@TODO")
	case reflect.Pointer:
		panic("@TODO")
	default:
		ret.WriteString(fmt.Sprintf("%#v", s))
	}
}



////////////////////////////////////////////////////////////////////////////////
// Parser
func convert_ast_to_reflect_type(struct_type ast.StructType) (reflect.Type, error) {
	var uninit reflect.Type

	fields := make([]reflect.StructField, len(struct_type.Fields.List))
	for i, field := range struct_type.Fields.List {
		if len(field.Names) != 1 {
			panic(fmt.Sprintf(`The field "%s.?" has zero or multiple names`, ""))
		}
		name := field.Names[0].Name

		tag := ``
		if field.Tag != nil {
			util.Assert(len(field.Tag.Value) > 2, "")
			last := len(field.Tag.Value) - 1
			util.Assert_eq(field.Tag.Value[0], "`"[0], "")
			util.Assert_eq(field.Tag.Value[last], "`"[0], "")
			tag = field.Tag.Value[1:]
		}

		var ty reflect.Type
		if name == "I" {
			ty = reflect.TypeOf([0]byte{})
		} else {
			switch token := field.Type.(type) {
			case *ast.StructType:
				var err error
				ty, err = convert_ast_to_reflect_type(*token)
				if err != nil {
					return uninit, err
				}
			case *ast.Ident:
				switch token.Name {
				case "string":
					ty = reflect.TypeOf("")
				case "bool":
					ty = reflect.TypeOf(false)
				default:
					return uninit, fmt.Errorf(`The field "%s" is of type %q. We only support string and bool for options`, name, token.Name)
				}
			default:
				return uninit, fmt.Errorf("The field \"%s\" is of type %T. It should be either\n1) named \"i\" for metadata struct tags\n2) of type \"bool\" or \"string\" for options\n3) of type \"struct\" for subcommands\n", name, token)
			}
		}
		fields[i] = reflect.StructField {
			Name: name,
			Type: ty,
			Tag:  reflect.StructTag(tag),
		}
	}
	return reflect.StructOf(fields), nil
}

func filter_for_top_level_ident(file_ast *ast.File, name string) (*ast.StructType, error) {
	for _, decl := range file_ast.Decls {
		gen_decl, ok := decl.(*ast.GenDecl)
		if !ok || gen_decl.Tok != token.TYPE {
			continue
			//copy(f.Decls[i:], f.Decls[i+1:])
			//f.Decls = f.Decls[:len(f.Decls)-1]
		}
		for _, spec := range gen_decl.Specs {
			type_spec, ok := spec.(*ast.TypeSpec)
			util.Assert(ok, "We already checked that the token type is token.TYPE")
			if type_spec.Name.Name != name {
				continue
			}
			if struct_type, ok := type_spec.Type.(*ast.StructType); ok {
				return struct_type, nil
			} else {
				return nil, fmt.Errorf("The type %q was not a struct", name)
			}
		}
	}
	return nil, fmt.Errorf("There was no top-level decleration named %q", name)
}

func find_source_code_for_top_level_func(src []byte, name string) ([]byte, error) {
	file_set := token.NewFileSet()
	file_ast, err := parser.ParseFile(file_set, "", src, 0)
	if err != nil {
		return nil, err
	}

	for _, decl := range file_ast.Decls {
		fn, ok := decl.(*ast.FuncDecl)
		if ok && name == fn.Name.Name {
			return src[fn.Pos() - 1:fn.End() - 1], nil
			//fmt.Println(fn.Name)
			//ast.Print(file_set, fn)
		}
	}
	return nil, fmt.Errorf("Could not find the function %q in the input.", name)
}
