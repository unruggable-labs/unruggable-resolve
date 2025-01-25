// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct Lookup {
    bytes dns;
    uint256 offset; // byte offset into dns for basename
    bytes32 node;
    bytes32 basenode;
    address resolver;
    bool extended;
    bool ok;
}

struct Response {
    uint256 bits; // ResponseBits
    bytes call; // record calldata
    bytes data; // answer (or error)
}

library ResponseBits {
    uint256 constant ERROR = 1 << 0; // resolution failed
    uint256 constant OFFCHAIN = 1 << 1; // reverted OffchainLookup
    uint256 constant BATCHED = 1 << 2; // used Batched Gateway
    uint256 constant RESOLVED = 1 << 3; // resolution finished (internal flag)
}

error LengthMismatch();

interface IUR {
    function lookupName(bytes memory dns) external view returns (Lookup memory lookup);
    function resolve(bytes memory dns, bytes[] memory calls, string[] memory batchedGateways)
        external
        view
        returns (Lookup memory lookup, Response[] memory res);
    function resolveCallback(bytes memory ccip, bytes memory batchedCarry)
        external
        view
        returns (Lookup memory lookup, Response[] memory res);
}
