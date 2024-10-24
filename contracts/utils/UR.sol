// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ENS} from "@ensdomains/ens-contracts/contracts/registry/ENS.sol";
import {IExtendedResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IExtendedResolver.sol";
import {BytesUtils} from "@ensdomains/ens-contracts/contracts/utils/BytesUtils.sol";
import {OffchainLookup} from "../CCIPReadProtocol.sol";
import {IBatchedGateway, BatchedGatewayQuery} from "./IBatchedGateway.sol";
import {IResolveMulticall} from "./IResolveMulticall.sol";

uint256 constant ERROR_BIT = 1 << 0; // resolution failed
uint256 constant OFFCHAIN_BIT = 1 << 1; // reverted OffchainLookup
uint256 constant BATCHED_BIT = 1 << 2; // used Batched Gateway
uint256 constant RESOLVED_BIT = 1 << 3; // resolution finished (internal flag)

contract UR {
    error Unreachable(bytes name);
    error LengthMismatch();

    ENS immutable _ens;
    string[] _batchedGateways;

    constructor(ENS ens, string[] memory batchedGateways) {
        _ens = ens;
        _batchedGateways = batchedGateways;
    }

    struct Response {
        uint256 bits;
        bytes data;
    }

    function resolve(
        bytes memory name,
        bytes[] memory calls,
        string[] memory batchedGateways
    ) external view returns (Lookup memory lookup, Response[] memory res) {
        lookup = lookupResolver(name); // do ensip-10
        res = new Response[](calls.length); // create result storage
        if (batchedGateways.length == 0) batchedGateways = _batchedGateways; // use default
        bytes[] memory offchainCalls = new bytes[](calls.length);
        uint256 offchain; // count how many offchain
        for (uint256 i; i < res.length; i++) {
            bytes memory call = lookup.extended
                ? abi.encodeCall(IExtendedResolver.resolve, (name, calls[i]))
                : calls[i];
            (bool ok, bytes memory v) = lookup.resolver.staticcall(call); // call it
            if (ok && lookup.extended) v = abi.decode(v, (bytes)); // unwrap resolve()
            res[i].data = v;
            if (!ok && bytes4(v) == OffchainLookup.selector) {
                res[i].bits |= OFFCHAIN_BIT | BATCHED_BIT;
                offchainCalls[offchain++] = calls[i];
            } else {
                if (!ok) res[i].bits |= ERROR_BIT;
                res[i].bits |= RESOLVED_BIT;
            }
        }
        if (offchain > 1) {
            // multiple records were offchain, try resolve(multicall)
            assembly {
                mstore(offchainCalls, offchain)
            }
            (bool ok, bytes memory v) = lookup.resolver.staticcall(
                abi.encodeCall(
                    IExtendedResolver.resolve,
                    (
                        name,
                        abi.encodeCall(
                            IResolveMulticall.multicall,
                            (offchainCalls)
                        )
                    )
                )
            );
            if (!ok && bytes4(v) == OffchainLookup.selector) {
                Response[] memory bundle = new Response[](1);
                bundle[0].data = v;
                _revertBatchedGateway(lookup, bundle, res, batchedGateways);
            }
        }
        if (offchain > 0) {
            _revertBatchedGateway(
                lookup,
                res,
                new Response[](0),
                batchedGateways
            );
        }
    }

    struct Lookup {
        uint256 offset; // byte offset into name
        bytes32 basenode;
        address resolver;
        bool extended; // if true, use resolve()
    }

    function lookupResolver(
        bytes memory name
    ) public view returns (Lookup memory lookup) {
        // https://docs.ens.domains/ensip/10
        unchecked {
            while (true) {
                lookup.basenode = BytesUtils.namehash(name, lookup.offset);
                lookup.resolver = _ens.resolver(lookup.basenode);
                if (lookup.resolver != address(0)) break;
                uint256 len = uint8(name[lookup.offset]);
                if (len == 0) revert Unreachable(name);
                lookup.offset += 1 + len;
            }
            if (
                _supportsInterface(
                    lookup.resolver,
                    type(IExtendedResolver).interfaceId
                )
            ) {
                lookup.extended = true;
            } else if (lookup.offset != 0) {
                revert Unreachable(name);
            }
        }
    }

    // batched gateway

    function _revertBatchedGateway(
        Lookup memory lookup,
        Response[] memory res,
        Response[] memory alt,
        string[] memory batchedGateways
    ) internal view {
        BatchedGatewayQuery[] memory queries = new BatchedGatewayQuery[](
            res.length
        );
        uint256 missing;
        for (uint256 i; i < res.length; i++) {
            if ((res[i].bits & RESOLVED_BIT) != 0) continue;
            (
                address sender,
                string[] memory urls,
                bytes memory request,
                ,

            ) = abi.decode(
                    _slice(res[i].data, 4),
                    (address, string[], bytes, bytes4, bytes)
                );
            queries[missing++] = BatchedGatewayQuery(sender, urls, request);
        }
        assembly {
            mstore(queries, missing)
        }
        revert OffchainLookup(
            address(this),
            batchedGateways,
            abi.encodeCall(IBatchedGateway.query, (queries)),
            this.batchedGatewayCallback.selector,
            abi.encode(lookup, res, alt, batchedGateways) // batchedCarry
        );
    }

    function batchedGatewayCallback(
        bytes memory ccip,
        bytes memory batchedCarry
    ) external view returns (Lookup memory lookup, Response[] memory res) {
        Response[] memory alt;
        string[] memory batchedGateways;
        (lookup, res, alt, batchedGateways) = abi.decode(
            batchedCarry,
            (Lookup, Response[], Response[], string[])
        );
        (bool[] memory failures, bytes[] memory responses) = abi.decode(
            ccip,
            (bool[], bytes[])
        );
        if (failures.length != responses.length) revert LengthMismatch();
        bool again;
        uint256 expected;
        for (uint256 i; i < res.length; i++) {
            if ((res[i].bits & RESOLVED_BIT) != 0) continue;
            if (failures[expected]) {
                res[i].bits |= ERROR_BIT | RESOLVED_BIT;
                res[i].data = responses[expected];
            } else {
                (
                    address sender,
                    ,
                    bytes memory request,
                    bytes4 selector,
                    bytes memory carry
                ) = abi.decode(
                        _slice(res[i].data, 4),
                        (address, string[], bytes, bytes4, bytes)
                    );

                (bool ok, bytes memory v) = sender.staticcall(
                    abi.encodeWithSelector(selector, responses[expected], carry)
                );
                if (
                    ok && bytes4(request) == IExtendedResolver.resolve.selector
                ) {
                    v = abi.decode(v, (bytes)); // unwrap resolve()
                }
                res[i].data = v;
                if (!ok && bytes4(v) == OffchainLookup.selector) {
                    again = true;
                } else {
                    if (!ok) res[i].bits |= ERROR_BIT;
                    res[i].bits |= RESOLVED_BIT;
                }
            }
            expected++;
        }
        if (expected != failures.length) revert LengthMismatch();
        if (again) {
            _revertBatchedGateway(lookup, res, alt, batchedGateways);
        }
        if (alt.length > 0) {
            if ((res[0].bits & ERROR_BIT) != 0) {
                // unsuccessful resolve(multicall) => call separately
                _revertBatchedGateway(
                    lookup,
                    alt,
                    new Response[](0),
                    batchedGateways
                );
            } else {
                _processMulticallAnswers(alt, res[0].data);
                res = alt; // unbundle
            }
        }
    }

    // utils

    function _processMulticallAnswers(
        Response[] memory res,
        bytes memory encoded
    ) internal pure {
        bytes[] memory answers = abi.decode(encoded, (bytes[]));
        uint256 expected;
        for (uint256 i; i < res.length; i++) {
            if ((res[i].bits & RESOLVED_BIT) == 0) {
                bytes memory v = answers[expected++];
                res[i].data = v;
                if ((v.length & 31) != 0) res[i].bits |= ERROR_BIT;
                res[i].bits |= RESOLVED_BIT;
            }
        }
        if (expected != answers.length) revert LengthMismatch();
    }

    function _supportsInterface(
        address a,
        bytes4 selector
    ) internal view returns (bool ret) {
        // https://eips.ethereum.org/EIPS/eip-165
        try IERC165(a).supportsInterface{gas: 30000}(selector) returns (
            bool quacks
        ) {
            ret = quacks;
        } catch {}
    }

    function _slice(
        bytes memory src,
        uint256 skip
    ) internal pure returns (bytes memory ret) {
        ret = abi.encodePacked(src);
        assembly {
            mstore(add(ret, skip), sub(mload(ret), skip))
            ret := add(ret, skip)
        }
    }
}
