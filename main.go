package main

import (
	"errors"
	"runtime"

	"github.com/containernetworking/cni/pkg/skel"
	"github.com/containernetworking/cni/pkg/version"
	bv "github.com/containernetworking/plugins/pkg/utils/buildversion"
)

func init() {
	// this ensures that main runs only on main thread (thread group leader).
	// since namespace ops (unshare, setns) are done for a single thread, we
	// must ensure that the goroutine does not jump from OS thread to thread
	runtime.LockOSThread()
}

func main() {
	skel.PluginMain(cmdAdd, cmdCheck, cmdDel, version.All, bv.BuildString("my-cni"))
}

func cmdAdd(args *skel.CmdArgs) error {
	return errors.New("Not Implemented")
}

func cmdDel(args *skel.CmdArgs) error {
	return errors.New("Not Implemented")
}

func cmdCheck(args *skel.CmdArgs) error {
	return errors.New("Not Implemented")
}
