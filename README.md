# PowerShell Street View Manager

## What is this?

This is a PowerShell script intended to help you manage Google Street View. It is essentially a wrapper for [the Street View Publish API](https://developers.google.com/streetview/publish/reference/rest).

## Usage

Before attempting to use any of the functionality, running the script once should throw an error but create the required `config.json` file. This file stores data related to the Google App you create which is used to authenticate with Google's services.

Once the configuration file is populated correctly, there are a couple of ways to use the script:

1. Run the script interactively with the `-I` switch. This will present you with menus and options that you can choose from.

2. Run the script via the script parameters. You can reference the parameters yourself by running `Get-Help ./Invoke-ManageStreetView.ps1`