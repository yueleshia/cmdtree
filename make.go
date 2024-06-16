package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"slices"

	"github.com/yueleshia/cmdtree/util"
)

//run: go run make.go -- examples
func main() {
	project_root, err := util.Find_go_root()
	if err != nil {
		util.LOG_STDERR.Fatalf("%s\n", err)
	}

	for _, arg := range os.Args[1:] {
		if arg == "--" {
			continue
		}
		util.LOG_STDERR.Printf("== make.go %q ==\n", arg)
		switch arg {
		case "build":
			sh("go", "build", filepath.Join(project_root, "util", "cmdtree", "main.go"))
		case "examples":
			for _, dir := range []string{"compiletime", "runtime"} {
				paths := util.Must(filepath.Glob(filepath.Join(project_root, "examples", dir, "*.go")))

				_, _ = os.Stderr.Write([]byte("-----\n"))
				sh("go", slices.Concat([]string{"generate"}, paths)...)
				sh("go", slices.Concat([]string{"run"}, paths, []string{"--help"})...)
			}
		default:
		}
	}
}


func sh(name string, args ...string) {
	cmd := exec.Command(name, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Run(); err != nil {
		util.LOG_STDERR.Fatalf("%s\n", err)
	}
}
