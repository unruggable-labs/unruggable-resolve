// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Digits {
    function length(uint256 value, uint256 radix) internal pure returns (uint256 len) {
        for (len = 1; value > radix; len += 1) {
            value /= radix;
        }
    }

    function append(uint256 ptr, uint256 len, uint256 value, uint256 radix) internal pure returns (uint256 dst) {
        unchecked {
            if (len == 0) len = length(value, radix);
            dst = ptr + len;
            while (len > 0) {
                uint256 x = value % radix;
                value /= radix;
                uint256 cp = (x < 10 ? 48 + x : 87 + x); // "0" => 48, ("a" - 10) => 87
                --len;
                assembly {
                    mstore8(add(ptr, len), cp)
                }
            }
        }
    }

    function appendHex(uint256 ptr, bytes memory v) internal pure returns (uint256 dst) {
        unchecked {
            uint256 src;
            uint256 len;
            assembly {
                src := add(v, 32)
                len := mload(v)
            }
            while (len >= 32) {
                uint256 x;
                assembly {
                    x := mload(src)
                    src := add(src, 32)
                    len := sub(len, 32)
                }
                ptr = append(ptr, 64, x, 16);
            }
            if (len > 0) {
                uint256 x;
                assembly {
                    x := mload(sub(src, sub(32, len)))
                }
                ptr = append(ptr, len << 1, x, 16);
            }
            return ptr;
        }
    }
}
