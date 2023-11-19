# Algorithmic Stablecoin

This protocol is a custom algorithmic stablecoin system, where the DSC token is pegged to the USD price at a 1:1 ratio (1 DSC = 1 $). The DSC token will be backed by two collateral tokens (ERC20): WETH and WBTC. Users can deposit either or both of these tokens and mint DSC tokens, they can hold the DSC tokens as long as their collateralization remains above the liquidation threshold (collateral value must be greater than double the minted DSC value, indicating a 200% collateralization ratio).

Additionally, the protocol will support flashloan operations, this will enable users to borrow either collateral (WETH or WBTC) tokens or DSC tokens, subject to a small fee paid to the protocol.

The project is built with foundry and uses the Openzeppelin and Chainlink as externals libraries.

## Key Features

* **DSC Minting/Burning**: Users are required to deposit collateral assets (WETH or WBTC) into the controller contract to mint DSC tokens. At any moment users will be able to burn the minted DSC tokens and withdraw their collateral.

* **Overcollateralization**: The protocol maintains a 200% collateralization ratio, ensuring that a user's collateral value always exceeds their minted DSC tokens. If a user falls below this threshold, their collateral will be liquidated to uphold protocol solvency and guarantee the DSC's peg to USD.

* **Flash Minting**: The controller will support flash minting of DSC tokens, allowing users to mint DSC tokens without the need for upfront collateral deposit.

* **Flash Loans**: Users have the option to perform flashloans on collateral tokens (WETH or WBTC) held in the controller.

* **Price Oracle**: Asset prices in USD are determined using the Chainlink oracle price feeds, ensuring reliable and up-to-date pricing information.
  
* **Protocol Fee**: The protocol only implements fees on flashloan operations, capped at a maximum of 1% of the amount borrowed.

* **Trusted Roles**: The protocol controller contract will be owned by the admin, who will only be allowed to perform the following operations: set a new flashloan fee, set a new fee recipient, pause or unpause flashloan operations. This admin will not have any access/control to the users colateral funds or to the DSC token minting/burning mechanism.

## Quick Start

```shell
$ git clone https://github.com/kaymen99/algorithmic-stablecoin
$ cd algorithmic-stablecoin
$ forge build
```

## Usage

### Deploy

```shell
$ forge script script/DeployDSC.s.sol:DeployDSC --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Runs all of the tests

```shell
$ forge test
```

### Displays the test coverage of the contracts

```shell
$ forge coverage
```

## Contact

I welcome any contributions, feel free to open issues, submit pull requests, or if you want to collaborate or have any questions, reach out to me: aymenMir1001@gmail.com

## License

Distributed under the MIT License. See `LICENSE.txt` for more information.
