// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// replacement for BytesUtils that supports encoded labels
// https://github.com/ensdomains/ens-contracts/blob/master/contracts/utils/BytesUtils.sol

// example codings:
// - ens: "aaa.bb.c"
// - dns: "3aaa2bb1c0"

// observations:
// - ens.length = dns.length - 2
// - ens is offset 1-byte with lengths replaced with "."

// WARNING: a label that contains a stop (.) will not round-trip
// decode("3a.b0) => revert InvalidDNSName
// encode("a.b") = "1a1b0"
// decode("1a1b0") = "a.b"

error MalformedDNSEncoding(bytes dns);
error DNSEncodingFailed(string name);

library DNSCoder {
    function decode(bytes memory dns) internal pure returns (string memory) {
        unchecked {
            uint256 n = dns.length;
            if (n == 1 && dns[0] == 0) return ""; // only valid answer is root
            if (n < 3) revert MalformedDNSEncoding(dns);
            bytes memory v = new bytes(n - 2); // always 2-shorter
            uint256 src = 0;
            uint256 dst = 0;
            while (src < n) {
                uint8 len = uint8(dns[src++]);
                if (len == 0) break;
                uint256 end = src + len;
                if (end > dns.length) revert MalformedDNSEncoding(dns); // overflow
                if (dst > 0) v[dst++] = ".";
                while (src < end) {
                    bytes1 x = dns[src++];
                    if (x == ".") revert MalformedDNSEncoding(dns); // malicious label
                    v[dst++] = x;
                }
            }
            if (src != dns.length) revert MalformedDNSEncoding(dns); // junk at end
            return string(v);
        }
    }

    function encode(string memory name) internal pure returns (bytes memory dns) {
        unchecked {
            uint256 n = bytes(name).length;
            if (n == 0) return hex"00"; // root
            dns = new bytes(n + 2); // always 2-longer
            uint256 w;
            uint256 e;
            uint256 r;
            assembly {
                e := add(dns, 32)
                r := e // remember start
                for {
                    let a := add(name, 32) // start of name
                    let b := add(a, n) // end of name
                } lt(a, b) { a := add(a, 1) } {
                    let x := shr(248, mload(a)) // read byte
                    if eq(x, 46) {
                        w := sub(e, r) // length of label
                        if or(iszero(w), gt(w, 255)) { break } // something wrong
                        mstore8(r, w) // store length at start
                        r := add(e, 1) // update start
                    }
                    {
                        e := add(e, 1)
                        mstore8(e, x)
                    }
                }
            }
            w = e - r; // length of last label
            if (w == 0 || w > 255) revert DNSEncodingFailed(name);
            assembly {
                mstore8(r, w) // store length
            }
        }
    }

    function namehash(bytes memory dns, uint256 offset) internal pure returns (bytes32 node, uint256 nextOffset) {
        (node, nextOffset) = readLabel(dns, offset); // reverts
        if (node == bytes32(0)) {
            if (nextOffset != dns.length) revert MalformedDNSEncoding(dns); // junk at end
        } else {
            (bytes32 parent,) = namehash(dns, nextOffset); // reverts
            assembly {
                mstore(0, parent)
                mstore(32, node)
                node := keccak256(0, 64)
            }
        }
    }

    function readLabel(bytes memory dns, uint256 offset)
        internal
        pure
        returns (bytes32 labelhash, uint256 nextOffset)
    {
        if (offset >= dns.length) revert MalformedDNSEncoding(dns); // expected size
        uint256 size = uint8(dns[offset++]);
        if (size == 0) return (bytes32(0), offset); // terminal
        nextOffset = offset + size;
        if (nextOffset > dns.length) revert MalformedDNSEncoding(dns); // expected length
        if (size == 66 && dns[offset] == "[" && dns[nextOffset - 1] == "]") {
            bool invalid;
            for (uint256 i; i < 64; i++) {
                uint256 a = uint8(dns[nextOffset - 2 - i]);
                if (a >= 48 && a <= 57) {
                    a -= 48;
                } else if (a >= 97 && a <= 102) {
                    a -= 87;
                } else {
                    invalid = true;
                    break;
                }
                labelhash |= bytes32(a << (i << 2));
            }
            if (!invalid) return (labelhash, nextOffset); // valid encoded label
        }
        assembly {
            labelhash := keccak256(add(dns, add(32, offset)), size)
        }
    }
}
