// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC165, IERC165} from "./ERC165.sol";
import {ENS} from "@ensdomains/ens-contracts/contracts/registry/ENS.sol";
import {IExtendedResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IExtendedResolver.sol";
import {BytesUtils} from "@ensdomains/ens-contracts/contracts/utils/BytesUtils.sol";
import {OffchainLookup, OffchainLookupTuple, CCIPReadProtocol} from "./CCIPReadProtocol.sol";
import {IBatchedGateway, BatchedGatewayQuery} from "./IBatchedGateway.sol";
import {IResolveMulticall} from "./IResolveMulticall.sol";
import {IUR, Lookup, Response, ResponseBits, LengthMismatch} from "./IUR.sol";

contract UR is IUR, IERC165 {
    ENS immutable _ens;
    string[] _batchedGateways;

    constructor(ENS ens, string[] memory batchedGateways) {
        _ens = ens;
        _batchedGateways = batchedGateways;
    }

    function gateways() external view returns (string[] memory) {
        return _batchedGateways;
    }

    function registry() external view returns (address) {
        return address(_ens);
    }

    function supportsInterface(bytes4 x) external pure returns (bool) {
        return type(IERC165).interfaceId == x || type(IUR).interfaceId == x;
    }

    function lookupName(bytes memory dns) public view returns (Lookup memory lookup) {
        // https://docs.ens.domains/ensip/10
        lookup.dns = dns;
        lookup.node = BytesUtils.namehash(dns, 0);
        while (true) {
            lookup.basenode = BytesUtils.namehash(dns, lookup.offset);
            lookup.resolver = _ens.resolver(lookup.basenode);
            if (lookup.resolver != address(0)) break;
            uint256 len = uint8(dns[lookup.offset]);
            if (len == 0) return lookup;
            lookup.offset += 1 + len;
        }
        if (ERC165.supportsInterface(lookup.resolver, type(IExtendedResolver).interfaceId)) {
            lookup.extended = true;
        } else if (lookup.offset != 0) {
            lookup.resolver = address(0);
        }
    }

    function resolve(bytes memory name, bytes[] memory calls, string[] memory batchedGateways)
        external
        view
        returns (Lookup memory lookup, Response[] memory res)
    {
        lookup = lookupName(name);
        if (lookup.resolver == address(0)) return (lookup, res);
        res = new Response[](calls.length); // create result storage
        if (batchedGateways.length == 0) batchedGateways = _batchedGateways; // use default
        bytes[] memory offchainCalls = new bytes[](calls.length);
        uint256 offchain; // count how many offchain
        for (uint256 i; i < res.length; i++) {
            Response memory r = res[i];
            bytes memory call = _injectNode(calls[i], lookup.node);
            r.call = call;
            if (lookup.extended) call = abi.encodeCall(IExtendedResolver.resolve, (name, call)); // wrap
            (bool ok, bytes memory v) = lookup.resolver.staticcall(call); // call it
            if (ok && lookup.extended) v = abi.decode(v, (bytes)); // unwrap
            r.data = v;
            if (!ok && bytes4(v) == OffchainLookup.selector) {
                r.bits |= ResponseBits.OFFCHAIN | ResponseBits.BATCHED;
                offchainCalls[offchain++] = calls[i];
            } else {
                if (!ok) r.bits |= ResponseBits.ERROR;
                r.bits |= ResponseBits.RESOLVED;
            }
        }
        if (offchain > 1) {
            // multiple records were offchain, try resolve(multicall)
            assembly {
                mstore(offchainCalls, offchain)
            }
            (bool ok, bytes memory v) = lookup.resolver.staticcall(
                abi.encodeCall(
                    IExtendedResolver.resolve, (name, abi.encodeCall(IResolveMulticall.multicall, (offchainCalls)))
                )
            );
            if (!ok && bytes4(v) == OffchainLookup.selector) {
                Response[] memory multi = new Response[](1);
                multi[0].data = v;
                _revertBatchedGateway(lookup, multi, res, batchedGateways);
            }
        }
        if (offchain > 0) {
            _revertBatchedGateway(lookup, res, new Response[](0), batchedGateways);
        }
    }

    // batched gateway

    function _revertBatchedGateway(
        Lookup memory lookup,
        Response[] memory res,
        Response[] memory alt,
        string[] memory batchedGateways
    ) internal view {
        BatchedGatewayQuery[] memory queries = new BatchedGatewayQuery[](res.length);
        uint256 missing;
        for (uint256 i; i < res.length; i++) {
            Response memory r = res[i];
            if ((r.bits & ResponseBits.RESOLVED) == 0) {
                OffchainLookupTuple memory x = CCIPReadProtocol.decode(r.data);
                queries[missing++] = BatchedGatewayQuery(x.sender, x.gateways, x.request);
            }
        }
        assembly {
            mstore(queries, missing)
        }
        revert OffchainLookup(
            address(this),
            batchedGateways,
            abi.encodeCall(IBatchedGateway.query, (queries)),
            this.resolveCallback.selector,
            abi.encode(lookup, res, alt, batchedGateways) // batchedCarry
        );
    }

    function resolveCallback(bytes memory ccip, bytes memory batchedCarry)
        external
        view
        returns (Lookup memory lookup, Response[] memory res)
    {
        Response[] memory alt;
        string[] memory batchedGateways;
        (lookup, res, alt, batchedGateways) = abi.decode(batchedCarry, (Lookup, Response[], Response[], string[]));
        (bool[] memory failures, bytes[] memory responses) = abi.decode(ccip, (bool[], bytes[]));
        if (failures.length != responses.length) revert LengthMismatch();
        bool again;
        uint256 expected;
        for (uint256 i; i < res.length; i++) {
            Response memory r = res[i];
            if ((r.bits & ResponseBits.RESOLVED) != 0) continue;
            if (failures[expected]) {
                r.bits |= ResponseBits.ERROR | ResponseBits.RESOLVED;
                r.data = responses[expected];
            } else {
                OffchainLookupTuple memory x = CCIPReadProtocol.decode(r.data);
                (bool ok, bytes memory v) =
                    x.sender.staticcall(abi.encodeWithSelector(x.selector, responses[expected], x.carry));
                if (ok && bytes4(x.request) == IExtendedResolver.resolve.selector) {
                    v = abi.decode(v, (bytes)); // unwrap resolve()
                }
                r.data = v;
                if (!ok && bytes4(v) == OffchainLookup.selector) {
                    again = true;
                } else {
                    if (!ok) r.bits |= ResponseBits.ERROR;
                    r.bits |= ResponseBits.RESOLVED;
                }
            }
            expected++;
        }
        if (expected != failures.length) revert LengthMismatch();
        if (again) {
            _revertBatchedGateway(lookup, res, alt, batchedGateways);
        }
        if (alt.length > 0) {
            if ((res[0].bits & ResponseBits.ERROR) != 0) {
                // unsuccessful resolve(multicall) => call separately
                _revertBatchedGateway(lookup, alt, new Response[](0), batchedGateways);
            } else {
                _processMulticallAnswers(alt, res[0].data);
                res = alt; // unbundle
            }
        }
    }

    // utils

    function _processMulticallAnswers(Response[] memory res, bytes memory encoded) internal pure {
        bytes[] memory m = abi.decode(encoded, (bytes[]));
        uint256 expected;
        for (uint256 i; i < res.length; i++) {
            Response memory r = res[i];
            if ((r.bits & ResponseBits.RESOLVED) == 0) {
                bytes memory v = m[expected++];
                r.data = v;
                if ((v.length & 31) != 0) r.bits |= ResponseBits.ERROR;
                r.bits |= ResponseBits.RESOLVED;
            }
        }
        if (expected != m.length) revert LengthMismatch();
    }

    function _injectNode(bytes memory v, bytes32 node) internal pure returns (bytes memory) {
        bool x;
        assembly {
            x := iszero(mload(add(v, 36)))
        }
        if (x) {
            v = abi.encodePacked(v);
            assembly {
                mstore(add(v, 36), node)
            }
        }
        return v;
    }
}
