// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {EVM_BIT} from "./Constants.sol";
import {Digits} from "./Digits.sol";

library ReverseName {

	function from(
		address addr,
		uint256 chain
	) internal pure returns (string memory) {
		return from(abi.encodePacked(addr), chain == 1 ? 60 : chain | EVM_BIT);
	}

    function from(
        bytes memory addr,
        uint256 coinType
    ) internal pure returns (string memory name) {
        // "{address}.("default"|"addr"|{chain.toString(10)}).reverse"
        if (coinType == EVM_BIT) {
			return _hexWithSuffix(addr, 1 + 7 + 1 + 7, 0x2e64656661756c742e7265766572736500000000000000000000000000000000);
		} else if (coinType == 60) {
			return _hexWithSuffix(addr, 1 + 4 + 1 + 7, 0x2e616464722e7265766572736500000000000000000000000000000000000000);
        } else {
			uint256 n = Digits.length(coinType, 10);
			name = new string((addr.length << 1) + 1 + n + 1 + 7);
			uint256 ptr;
			assembly {
				ptr := add(name, 32)
			}
			ptr = Digits.appendHex(ptr, addr);
			assembly {
				mstore8(ptr, 0x2e)
				ptr := add(ptr, 1)
			}
            ptr = Digits.append(ptr, n, coinType, 10);
			assembly {
				mstore(ptr, 0x2e72657665727365000000000000000000000000000000000000000000000000)
			}
        }
    }

	function _hexWithSuffix(bytes memory v, uint256 n, uint256 x) internal pure returns (string memory ret) {
		ret = new string((v.length << 1) + n);
		uint256 ptr;
		assembly {
			ptr := add(ret, 32)
		}
		ptr = Digits.appendHex(ptr, v);
		assembly {
			mstore(ptr, x)
		}
	}

}
