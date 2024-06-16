package util

import (
  "fmt"
	"os"
	"path/filepath"
)

func Find_go_root() (string, error) {
	dir, err := os.Getwd()
	if err != nil {
		return "", err
	}

	for i := 0; i < 100; i += 1 {
		_, err := os.Stat(filepath.Join(dir, "go.mod"))
		if os.IsNotExist(err) {
			dir = filepath.Dir(dir)
		} else {
			return dir, nil
		}
	}
	return "", fmt.Errorf("Could not find directory with go.mod in parent hierarchy\n")
}

