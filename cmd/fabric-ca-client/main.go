/*
Copyright IBM Corp. All Rights Reserved.

SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"os"

	"github.com/hyperledger/fabric-ca/cmd/fabric-ca-client/command"
)

// The fabric-ca client main
func main() {
	if err := command.RunMain(os.Args); err != nil {
		os.Exit(1)
	}
}
