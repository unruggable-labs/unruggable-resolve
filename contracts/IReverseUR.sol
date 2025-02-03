// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUR, Lookup} from "./IUR.sol";

interface IReverseUR {
    function ur() external view returns (IUR);
    function reverseName(bytes memory addr, uint256 coinType) external pure returns (string memory);
    function reverse(bytes memory addr, uint256 coinType, string[] memory batchedGateways)
        external
        view
        returns (Lookup memory rev, Lookup memory fwd, bytes memory answer);
}
