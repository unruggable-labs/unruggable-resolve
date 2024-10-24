// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IResolveMulticall {
    function multicall(bytes[] calldata) external view returns (bytes[] memory);
}
