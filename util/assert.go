// Helper primitives inspired by rust

package util

import (
	"fmt"
)

// Well this a go idiom, but yeah
func Must[T any](obj T, err error) T {
	if err != nil {
		panic(err)
	}
	return obj
}

func Unwrap[T any](obj T, err error) T {
	if err != nil {
		LOG_STDERR.Fatalln(err)
	}
	return obj
}

type HasEquality interface {
	~string |
		~bool |
		~uint8 | ~uint16 | ~uint32 | ~uint64 | ~uint | ~int8 | ~int16 | ~int32 | ~int64 | ~int | ~float32 | ~float64 | ~complex64 | ~complex128
}

func Assert(ok bool, msg string) {
	if !ok {
		panic(msg)
	}
}

func Assert_eq[T HasEquality](a, b T, msg string) {
	if a != b {
		panic(fmt.Sprintf("%s\nExpected: %#v\nRecieved: %#v\n", msg, a, b))
	}
}

func Assert_ne[T HasEquality](a, b T, msg string) {
	if a == b {
		panic(fmt.Sprintf("%s\nRecieved: %#v\n", msg, a, b))
	}
}
