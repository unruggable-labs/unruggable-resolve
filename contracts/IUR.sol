// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct Response {
    uint256 bits;
    bytes data;
}

struct Lookup {
    bytes dns;
    uint256 offset; // byte offset into dns
    bytes32 basenode;
    address resolver;
    bool extended; // if true, use resolve()
    bool ok;
}

library ResponseBits {
    uint256 constant ERROR = 1 << 0; // resolution failed
    uint256 constant OFFCHAIN = 1 << 1; // reverted OffchainLookup
    uint256 constant BATCHED = 1 << 2; // used Batched Gateway
    uint256 constant RESOLVED = 1 << 3; // resolution finished (internal flag)
}

error Unreachable(bytes name);
error LengthMismatch();

interface IUR {
    function lookupName(bytes memory dns) external view returns (Lookup memory lookup);
    function resolve(bytes memory name, bytes[] memory calls, string[] memory batchedGateways)
        external
        view
        returns (Lookup memory lookup, Response[] memory res);
    function resolveCallback(bytes memory ccip, bytes memory batchedCarry)
        external
        view
        returns (Lookup memory lookup, Response[] memory res);
}
