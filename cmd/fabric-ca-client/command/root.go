/*
Copyright IBM Corp. All Rights Reserved.

SPDX-License-Identifier: Apache-2.0
*/

package command

import "os"

// RunMain is the fabric-ca client main
func RunMain(args []string) error {
	// Save the os.Args
	saveOsArgs := os.Args
	os.Args = args

	// Execute the command
	cmdName := ""
	if len(args) > 1 {
		cmdName = args[1]
	}
	ccmd := NewCommand(cmdName)
	err := ccmd.Execute()

	// Restore original os.Args
	os.Args = saveOsArgs

	return err
}
