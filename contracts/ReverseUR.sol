// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {BytesUtils} from "@ensdomains/ens-contracts/contracts/utils/BytesUtils.sol";
import {INameResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/INameResolver.sol";
import {IAddressResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IAddressResolver.sol";
import {IAddrResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IAddrResolver.sol";
import {IUR, Lookup, Response, ResponseBits} from "./IUR.sol";
import {OffchainLookup} from "./CCIPReadProtocol.sol";
import {ReverseName} from "./ReverseName.sol";
import {ENSDNSCoder} from "./ENSDNSCoder.sol";
import {EVM_BIT} from "./Constants.sol";

import "forge-std/console2.sol";

contract ReverseUR {
    IUR immutable _ur;

    constructor(address ur) {
        _ur = IUR(ur);
    }

    function reverse(bytes memory addr, uint256 coinType, string[] memory batchedGateways)
        external
        view
        returns (Lookup memory, /*rev*/ Lookup memory, /*fwd*/ bytes memory /*answer*/ )
    {
        bytes memory v = _lookupName(addr, coinType, coinType, batchedGateways);
        assembly {
            return(add(v, 32), mload(v))
        }
    }

    function _lookupName(bytes memory addr, uint256 coinType, uint256 coinType0, string[] memory batchedGateways)
        internal
        view
        returns (bytes memory)
    {
        string memory name = ReverseName.from(addr, coinType);
        console2.log("name: %s", name);
        bytes memory dns = ENSDNSCoder.dnsEncode(name);
        bytes32 node = BytesUtils.namehash(dns, 0);
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeCall(INameResolver.name, (node));
        return _wrap(
            abi.encodeCall(IUR.resolve, (dns, calls, batchedGateways)),
            this.reverseCallback1.selector,
            abi.encode(Reverse1(addr, coinType, coinType0, batchedGateways))
        );
    }

    struct WrapCarry {
        bytes4 urCallback;
        bytes urCarry;
        bytes4 myCallback;
        bytes myCarry;
    }

    function _wrap(bytes memory call, bytes4 mySelector, bytes memory myCarry) internal view returns (bytes memory) {
        (bool ok, bytes memory v) = address(_ur).staticcall(call);
        if (!ok && bytes4(v) == OffchainLookup.selector) {
            (address sender, string[] memory gateways, bytes memory request, bytes4 urSelector, bytes memory urCarry) =
                abi.decode(_dropSelector(v), (address, string[], bytes, bytes4, bytes));
            if (sender != address(_ur)) revert("expected UR");
            revert OffchainLookup(
                address(this),
                gateways,
                request,
                this.wrapCallback.selector,
                abi.encode(WrapCarry(urSelector, urCarry, mySelector, myCarry))
            );
        }
        if (ok) {
            (Lookup memory lookup, Response[] memory res) = abi.decode(v, (Lookup, Response[]));
            console2.log("UR: %s = %s (%s)", ENSDNSCoder.dnsDecode(lookup.dns), lookup.ok, res.length);
            (ok, v) = address(this).staticcall(abi.encodeWithSelector(mySelector, lookup, res, myCarry));
        }
        if (!ok) {
            assembly {
                revert(add(v, 32), mload(v))
            }
        }
        return v;
    }

    function wrapCallback(bytes memory ccip, bytes memory carry) external view {
        WrapCarry memory state = abi.decode(carry, (WrapCarry));
        bytes memory v =
            _wrap(abi.encodeWithSelector(state.urCallback, ccip, state.urCarry), state.myCallback, state.myCarry);
        assembly {
            return(add(v, 32), mload(v))
        }
    }

    struct Reverse1 {
        bytes addr;
        uint256 coinType;
        uint256 coinType0;
        string[] batchedGateways;
    }

    function reverseCallback1(Lookup memory lookup, Response[] memory res, bytes memory carry)
        external
        view
        returns (Lookup memory, Lookup memory nul, bytes memory)
    {
        console2.log("callback1");
        Reverse1 memory state = abi.decode(carry, (Reverse1));
        bytes memory v;
        if (!lookup.ok || (res[0].bits & ResponseBits.ERROR) != 0 || _tryDecodeBytes(res[0].data).length == 0) {
            if (!_isEVMCoinType(state.coinType)) return (lookup, nul, "");
            v = _lookupName(state.addr, EVM_BIT, state.coinType0, state.batchedGateways);
        } else {
            bytes memory dns = ENSDNSCoder.dnsEncode(abi.decode(res[0].data, (string)));
            bytes32 node = BytesUtils.namehash(dns, 0);
            bytes[] memory calls = new bytes[]((state.coinType == EVM_BIT && state.coinType0 != EVM_BIT) ? 4 : 1);
            calls[0] = abi.encodeCall(IAddressResolver.addr, (node, state.coinType0));
            if (calls.length > 1) {
                calls[1] = abi.encodeCall(IAddressResolver.addr, (node, EVM_BIT));
                calls[2] = abi.encodeCall(IAddressResolver.addr, (node, 60));
                calls[3] = abi.encodeCall(IAddrResolver.addr, (node));
            }
            console2.log("calls: %s", calls.length);
            v = _wrap(
                abi.encodeCall(IUR.resolve, (dns, calls, state.batchedGateways)),
                this.reverseCallback2.selector,
                abi.encode(Reverse2(state.addr, state.coinType, state.batchedGateways, lookup))
            );
        }
        assembly {
            return(add(v, 32), mload(v))
        }
    }

    struct Reverse2 {
        bytes addr;
        uint256 coinType;
        string[] batchedGateways;
        Lookup rev;
    }

    function reverseCallback2(Lookup calldata lookup, Response[] calldata res, bytes memory carry)
        external
        pure
        returns (Lookup memory rev, Lookup memory fwd, bytes memory answer)
    {
        console2.log("callback2");
        Reverse2 memory state = abi.decode(carry, (Reverse2));
        rev = state.rev;
        fwd = lookup;
        if (fwd.ok) {
            for (uint256 i; i < res.length; i++) {
                console2.log("[%s] %s", i, res[i].bits);
                console2.logBytes(res[i].data);
                if ((res[i].bits & ResponseBits.ERROR) != 0) continue;
                bytes memory v = res[i].data;
                if (v.length != 32) v = _tryDecodeBytes(v);
                if (_isZeros(v)) continue;
                answer = v;
                break;
            }
        }
    }

    function _dropSelector(bytes memory v) internal pure returns (bytes memory ret) {
        return BytesUtils.substring(v, 4, v.length - 4);
    }

    function _isEVMCoinType(uint256 coinType) internal pure returns (bool) {
        return coinType == 60 || (uint32(coinType) == coinType && (coinType & EVM_BIT) != 0 && coinType != EVM_BIT);
    }

    function _isZeros(bytes memory v) internal pure returns (bool ret) {
        assembly {
            let p := add(v, 32)
            let e := add(p, mload(v))
            let x
            ret := 1
            for {} lt(p, e) {} {
                x := mload(p)
                p := add(p, 32)
                if x {
                    ret := 0
                    break
                }
            }
            if and(gt(p, e), iszero(ret)) { ret := iszero(shr(shl(3, sub(p, e)), x)) }
        }
    }

    function _tryDecodeBytes(bytes memory v) internal pure returns (bytes memory ret) {
        uint256 n;
        assembly {
            n := add(32, mload(add(v, 32)))
            n := add(n, mload(add(v, n)))
        }
        if (v.length >= n) ret = abi.decode(v, (bytes));
    }
}
