// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ENS} from "@ensdomains/ens-contracts/contracts/registry/ENS.sol";
import {IExtendedResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IExtendedResolver.sol";
import {INameResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/INameResolver.sol";
import {IAddressResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IAddressResolver.sol";
import {BytesUtils} from "@ensdomains/ens-contracts/contracts/utils/BytesUtils.sol";
import {OffchainLookup} from "./CCIPReadProtocol.sol";
import {IBatchedGateway, BatchedGatewayQuery} from "./IBatchedGateway.sol";
import {ENSIP10, Lookup} from "./ENSIP10.sol";
import {ReverseName} from "./ReverseName.sol";
import {ENSDNSCoder} from "./ENSDNSCoder.sol";
import {IResolveMulticall} from "./IResolveMulticall.sol";
import {EVM_BIT} from "./Constants.sol";

import "forge-std/console2.sol";

contract RR {
    ENS immutable _ens;
    string[] _batchedGateways;

    constructor(ENS ens, string[] memory batchedGateways) {
        _ens = ens;
        _batchedGateways = batchedGateways;
    }

    function reverse(
        bytes memory addr,
        uint256 coinType,
        string[] memory batchedGateways
    )
        external
        view
        returns (
            Lookup memory rev_lookup,
            Lookup memory fwd_lookup,
            bytes memory fwd_addr
        )
    {
        if (batchedGateways.length == 0) batchedGateways = _batchedGateways;
        bytes memory rev_dns = ENSDNSCoder.dnsEncode(
            ReverseName.from(addr, coinType)
        );
        rev_lookup = ENSIP10.lookupResolver(_ens, rev_dns);
        if (rev_lookup.ok) {
            (bool ok, bytes memory v) = _callResolver(
                rev_lookup,
                rev_dns,
                abi.encodeCall(
                    INameResolver.name,
                    (BytesUtils.namehash(rev_dns, 0))
                ),
                batchedGateways,
                this.reverse2.selector,
                abi.encode(Reverse2(coinType, rev_lookup, batchedGateways))
            );
            if (ok) {
                assembly {
                    return(add(v, 32), mload(v))
                }
            } else {
                assembly {
                    revert(add(v, 32), mload(v))
                }
            }
        }
    }

    struct Reverse2 {
        uint256 coinType;
        Lookup rev_lookup;
        string[] batchedGateways;
    }

    function reverse2(
        bytes memory response,
        bytes memory carry
    )
        external
        view
        returns (
            Lookup memory rev_lookup,
            Lookup memory fwd_lookup,
            bytes memory addr
        )
    {
        Reverse2 memory state = abi.decode(carry, (Reverse2));
        rev_lookup = state.rev_lookup;
        addr = response;
        if (response.length & 31 == 0) {
            bytes memory dns = ENSDNSCoder.dnsEncode(
                abi.decode(response, (string))
            );
            fwd_lookup = ENSIP10.lookupResolver(_ens, dns);
            if (fwd_lookup.ok) {
                bytes32 node = BytesUtils.namehash(dns, 0);
                bytes memory call = abi.encodeCall(
                    IAddressResolver.addr,
                    (node, state.coinType)
                );
                if (_isEVMCoinType(state.coinType)) {
                    bytes[] memory calls = new bytes[](2);
                    calls[0] = call;
                    calls[1] = abi.encodeCall(
                        IAddressResolver.addr,
                        (node, EVM_BIT)
                    );
                    call = abi.encodeCall(IResolveMulticall.multicall, (calls));
                }
                (bool ok, bytes memory v) = _callResolver(
                    fwd_lookup,
                    dns,
                    call,
                    state.batchedGateways,
                    this.reverse3.selector,
                    abi.encode(Reverse3(state, fwd_lookup))
                );
                if (ok) {
                    assembly {
                        return(add(v, 32), mload(v))
                    }
                } else {
                    assembly {
                        revert(add(v, 32), mload(v))
                    }
                }
            }
        }
    }

    struct Reverse3 {
        Reverse2 prior;
        Lookup fwd_lookup;
    }

    function reverse3(
        bytes memory response,
        bytes memory carry
    )
        external
        pure
        returns (
            Lookup memory rev_lookup,
            Lookup memory fwd_lookup,
            bytes memory addr
        )
    {
        Reverse3 memory state = abi.decode(carry, (Reverse3));
        rev_lookup = state.prior.rev_lookup;
        fwd_lookup = state.fwd_lookup;
        if (response.length & 31 != 0) {
            // error reading address
            addr = response;
        } else if (_isEVMCoinType(state.prior.coinType)) {
            bytes[] memory m = abi.decode(response, (bytes[]));
            for (uint256 i; i < m.length; i++) {
                console2.logBytes(m[i]);
            }

            bool ok0 = m[0].length & 31 == 0;
            bool ok1 = m[1].length & 31 == 0;
            if (ok0) {
                addr = abi.decode(m[0], (bytes));
            }
            if (addr.length == 0 && ok1) {
                addr = abi.decode(m[1], (bytes));
            }
            if (!ok0 && !ok1) {
                addr = m[0];
            }
        } else {
            addr = abi.decode(response, (bytes));
        }
    }

    function _isEVMCoinType(uint256 coinType) internal pure returns (bool) {
        return
            coinType == 60 ||
            (uint32(coinType) == coinType &&
                (coinType & EVM_BIT) != 0 &&
                coinType != EVM_BIT);
    }

    function _callResolver(
        Lookup memory lookup,
        bytes memory dns,
        bytes memory call0
    ) internal view returns (bool ok, bytes memory v) {
        bytes memory call = lookup.extended
            ? abi.encodeCall(IExtendedResolver.resolve, (dns, call0))
            : call0;
        (ok, v) = lookup.resolver.staticcall(call);
        if (ok && lookup.extended) {
            v = abi.decode(v, (bytes));
        }
        if (v.length & 31 != (ok ? 0 : 4)) {
            revert("wtf encoding");
        }
    }

    function _callResolver(
        Lookup memory lookup,
        bytes memory dns,
        bytes memory call0,
        string[] memory batchedGateways,
        bytes4 callback,
        bytes memory carry
    ) internal view returns (bool, bytes memory) {
        bytes[] memory m;
        (bool ok, bytes memory v) = _callResolver(lookup, dns, call0);
        if (bytes4(call0) == IResolveMulticall.multicall.selector) {
            bytes[] memory calls = abi.decode(_dropSelector(call0), (bytes[]));
            if (calls.length < 2) revert("wtf bro");
            m = new bytes[](1 + calls.length);
            for (uint256 i; i < calls.length; i++) {
                (, m[i + 1]) = _callResolver(lookup, dns, calls[i]);
            }
        } else {
            m = new bytes[](1);
        }
        m[0] = v;
        if (!ok) {
            bool offchain = bytes4(v) == OffchainLookup.selector;
            if (offchain || m.length > 1) {
                return
                    address(this).staticcall(
                        abi.encodeCall(
                            this._revertBatchedGateway,
                            (offchain, m, batchedGateways, callback, carry)
                        )
                    );
            }
        }
        return
            address(this).staticcall(
                abi.encodeWithSelector(callback, v, carry)
            );
    }

    function _queryFromRevert(
        bytes memory data
    ) internal pure returns (BatchedGatewayQuery memory) {
        (address sender, string[] memory urls, bytes memory request, , ) = abi
            .decode(
                _dropSelector(data),
                (address, string[], bytes, bytes4, bytes)
            );
        return BatchedGatewayQuery(sender, urls, request);
    }

    function _isOK(bytes memory v) internal pure returns (bool) {
        return v.length & 31 == 0;
    }

    function _revertBatchedGateway(
        bool multi,
        bytes[] memory answers,
        string[] memory batchedGateways,
        bytes4 callback,
        bytes memory carry
    ) public view {
        BatchedGatewayQuery[] memory queries;
        uint256[] memory offchain;
        bytes memory response;
        console2.log("batched gateway: %s %s", multi, answers.length);
        if (multi) {
            if (
                answers[0].length & 31 != 0 &&
                bytes4(answers[0]) == OffchainLookup.selector
            ) {
                queries = new BatchedGatewayQuery[](1);
                queries[0] = _queryFromRevert(answers[0]);
                offchain = new uint256[](1);
            } else {
                response = answers[0];
            }
        } else {
            offchain = new uint256[](answers.length - 1);
            uint256 count;
            for (uint256 i = 1; i < answers.length; i++) {
                if (
                    answers[i].length & 32 != 0 &&
                    bytes4(answers[i]) == OffchainLookup.selector
                ) {
                    offchain[count++] = i;
                }
            }
            assembly {
                mstore(offchain, count)
            }
            if (count == 0) {
                response = abi.encode(answers);
            } else {
                queries = new BatchedGatewayQuery[](count);
                for (uint256 i; i < count; i++) {
                    queries[i] = _queryFromRevert(answers[offchain[i]]);
                }
            }
        }
        if (offchain.length == 0) {
            (bool ok, bytes memory v) = address(this).staticcall(
                abi.encodeWithSelector(callback, response, carry)
            );
            if (ok) {
                assembly {
                    return(add(v, 32), mload(v))
                }
            } else {
                assembly {
                    revert(add(v, 32), mload(v))
                }
            }
        } else {
            revert OffchainLookup(
                address(this),
                batchedGateways,
                abi.encodeCall(IBatchedGateway.query, (queries)),
                this.batchedGatewayCallback.selector,
                abi.encode(
                    BatchedGateway(
                        offchain,
                        answers,
                        batchedGateways,
                        callback,
                        carry
                    )
                )
            );
        }
    }

    struct BatchedGateway {
        uint256[] offchain;
        bytes[] answers;
        string[] batchedGateways;
        bytes4 callback;
        bytes carry;
    }

    function batchedGatewayCallback(
        bytes memory response,
        bytes memory batchedCarry
    ) external view {
        BatchedGateway memory state = abi.decode(
            batchedCarry,
            (BatchedGateway)
        );
        (bool[] memory failures, bytes[] memory responses) = abi.decode(
            response,
            (bool[], bytes[])
        );
        if (responses.length != failures.length) revert("wtf length");
        if (responses.length != state.offchain.length) revert("wtf length");
        bool multi = state.offchain[0] == 0;
        bool ok;
        bytes memory v;
        if (multi && failures[0]) {
            multi = false;
        } else {
            for (uint256 i; i < state.offchain.length; i++) {
                uint256 j = state.offchain[i];
                if (failures[i]) {
                    state.answers[j] = responses[i];
                } else {
                    (
                        address sender,
                        ,
                        bytes memory request,
                        bytes4 selector,
                        bytes memory carry
                    ) = abi.decode(
                            _dropSelector(state.answers[j]),
                            (address, string[], bytes, bytes4, bytes)
                        );
                    (ok, v) = sender.staticcall(
                        abi.encodeWithSelector(selector, responses[i], carry)
                    );
                    if (
                        ok &&
                        bytes4(request) == IExtendedResolver.resolve.selector
                    ) {
                        v = abi.decode(v, (bytes)); // unwrap resolve()
                    }
                    state.answers[j] = v;
                }
            }
        }
        (ok, v) = address(this).staticcall(
            abi.encodeCall(
                this._revertBatchedGateway,
                (
                    multi,
                    state.answers,
                    state.batchedGateways,
                    state.callback,
                    state.carry
                )
            )
        );
        if (ok) {
            assembly {
                return(add(v, 32), mload(v))
            }
        } else {
            assembly {
                revert(add(v, 32), mload(v))
            }
        }
    }

    function _dropSelector(
        bytes memory v
    ) internal pure returns (bytes memory ret) {
        return BytesUtils.substring(v, 4, v.length - 4);
    }
}
