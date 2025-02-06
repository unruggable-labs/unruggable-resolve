# Unruggable Resolve

* [**UR.sol**](./contracts/UR.sol) &mdash; single contract to encapsulate [ENSIP-10](https://docs.ens.domains/ensip/10) + Hybrid Multicall + Batched Gateway (to avoid CCIP-Read failures)
	* standard interface: [**IUR.sol**](./contracts/IUR.sol)
	* designed to be wrapped
	* `lookupName(bytes dns) view returns (Lookup)`
	* `resolve(bytes dns, bytes[] calls) view returns (Lookup, Responses[])`
* [**ReverseUR.sol**](./contracts/ReverseUR.sol) &mdash; an entrypoint for Reverse resolution
	* standard interface: [**IUR.sol**](./contracts/IReverseUR.sol)
	* uses UR internally
	* `reverse(bytes addr, uint256 coinType) returns view (Lookup fev, Lookup fwd, bytes addr)`
* [**UnruggableUR.sol**](./contracts/UnruggableUR.sol) &mdash; code-free ENS entrypoint with human-readable I/O:
	* uses UR internally
	* `resolve(string name, string[] textKeys, uint256[] coinTypes, bool contentHash) returns view (Lookup, string[] texts, string[] addrs, bytes contentHash)`

### Utilities

* [**DNSCoder.sol**](./contracts/DNSCoder.sol)
	* convert between ENS (`"raffy.eth"`) and DNS-Encoded (`0x0572616666790365746800`)
	* convert DNS-Encoded to namehash (`0x9c8b7ac505c9f0161bbbd04437fce8c630a0886e1ffea00078e298f063a8a5df`)
* [**ReverseName.sol**](./contracts/ReverseName.sol) &mdash; generate multichain address reverse names
	* `60` &rarr; `"51050ec063d393217b436747617ad1c2285aeeee.addr.reverse"`
	* `0x80000000` &rarr; `"51050ec063d393217b436747617ad1c2285aeeee.default.reverse"`
