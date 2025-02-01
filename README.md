# Unruggable Contracts

A repository of contracts including:

* [**UR.sol**](./contracts/UR.sol) &mdash; single contract to encapsulate ENSIP-10 + Hybrid Multicall + Batched Gateway (to avoid CCIP-Read failures)
	* standard interface: [**IUR.sol**](./contracts/IUR.sol)
	* designed to be Wrapped
	* `lookupName(bytes dns) view returns (Lookup)`
	* `resolve(bytes dns, bytes[] calls) view returns (Lookup, Responses[])`
* [**ReverseUR.sol**](./contracts/ReverseUR.sol) &mdash; an entrypoint for Reverse resolution
	* uses UR internally
	* `reverse(bytes addr, uint256 coinType) returns view (Lookup fev, Lookup fwd, bytes addr)`
* [**UnruggableUR.sol**](./contracts/UnruggableUR.sol) &mdash; code-free ENS entrypoint with human-readable I/O:
	* uses UR internally
	* `resolve(string name, string[] textKeys, uint256[] coinTypes, bool contentHash) returns view (Lookup, string[] texts, string[] addrs, bytes contentHash)`

### Utilities

* [**ENSDNSCoder.sol**](./contracts/ENSDNSCoder.sol) &mdash; convert between ENS (`"raffy.eth"`) and DNS-Encoded (`0x0572616666790365746800`)
* [**ReverseName.sol**](./contracts/ReverseName.sol) &mdash; generate multichain address reverse names (`"0x51050ec063d393217B436747617aD1C2285Aeeee" + CoinType(0x80000000)` &rarr; `"51050ec063d393217b436747617ad1c2285aeeee.default.reverse"`)

