/*
Copyright IBM Corp. All Rights Reserved.

SPDX-License-Identifier: Apache-2.0
*/

package command

import (
	"path/filepath"

	"github.com/cloudflare/cfssl/log"
	"github.com/pkg/errors"
	"github.com/spf13/cobra"
)

func (c *ClientCmd) newGenCsrCommand() *cobra.Command {
	// initCmd represents the init command
	gencsrCmd := &cobra.Command{
		Use:   "gencsr",
		Short: "Generate a CSR",
		Long:  "Generate a Certificate Signing Request for an identity",
		PreRunE: func(cmd *cobra.Command, args []string) error {
			if len(args) > 0 {
				return errors.Errorf(extraArgsError, args, cmd.UsageString())
			}

			err := c.ConfigInit()
			if err != nil {
				return err
			}

			log.Debugf("Client configuration settings: %+v", c.clientCfg)

			return nil
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			err := c.runGenCSR(cmd)
			if err != nil {
				return err
			}
			return nil
		},
	}
	gencsrCmd.Flags().StringVar(&c.csrCommonName, "csr.cn", "", "The common name for the certificate signing request")
	return gencsrCmd
}

// The gencsr main logic
func (c *ClientCmd) runGenCSR(cmd *cobra.Command) error {
	log.Debug("Entered runGenCSR")

	if c.csrCommonName != "" {
		c.clientCfg.CSR.CN = c.csrCommonName
	}

	err := c.clientCfg.GenCSR(filepath.Dir(c.cfgFileName))
	if err != nil {
		return err
	}

	return nil
}
