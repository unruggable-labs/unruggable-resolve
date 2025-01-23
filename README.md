# Unruggable Contracts

A repository of contracts including:

* [**UR.sol**](./contracts/utils/UR.sol) &mdash; a Universal Resolver, that can be used to resolve ENS names using a batched gateway. 
* [**ReverseUR.sol**](./contracts/utils/ReverseUR.sol) &mdash; a Universal Reverse Resolver, for cross-chain primary name and address resolution.
	* uses UR internally
* [**ENSDNSCoder.sol**](./contracts/utils/ENSDNSCoder.sol) &mdash; convert between ENS (`"raffy.eth"`) and DNS-Encoded (`0x0572616666790365746800`)
