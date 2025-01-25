// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {EVM_BIT, COIN_TYPE_ETH} from "./Constants.sol";
import {Digits} from "./Digits.sol";

library ReverseName {
    function from(address addr, uint256 chain) internal pure returns (string memory) {
        return from(abi.encodePacked(addr), chain == 1 ? COIN_TYPE_ETH : (chain | EVM_BIT));
    }

    function from(bytes memory addr, uint256 coinType) internal pure returns (string memory name) {
        // https://docs.ens.domains/ensip/19
        // "{address}.("default"|"addr"|{chain.toString(16)}).reverse"
        uint256 size;
        uint256 radix;
        uint256 suffix;
        if (coinType == EVM_BIT) {
            suffix = 0x2e64656661756c742e7265766572736500000000000000000000000000000000; // ".default.reverse"
            size = 7;
        } else if (coinType == COIN_TYPE_ETH) {
            suffix = 0x2e616464722e7265766572736500000000000000000000000000000000000000; // ".addr.reverse"
            size = 4;
        } else {
            suffix = 0x2e72657665727365000000000000000000000000000000000000000000000000; // ".reverse"
            radix = 16;
            size = Digits.length(coinType, radix);
        }
        name = new string((addr.length << 1) + size + 9); // length("..reverse")
        uint256 ptr;
        assembly {
            ptr := add(name, 32)
        }
        ptr = Digits.appendHex(ptr, addr); // hex
        if (radix != 0) {
            assembly {
                mstore8(ptr, 0x2e) // "."
                ptr := add(ptr, 1)
            }
            ptr = Digits.append(ptr, size, coinType, radix); // chain
        }
        assembly {
            mstore(ptr, suffix)
        }
    }
}
