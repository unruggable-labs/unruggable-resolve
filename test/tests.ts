import type { Foundry } from "@adraffy/blocksmith";
import type { createResolve } from "./UR.js";
import { test, expect } from "bun:test";
import { namehash, solidityPackedKeccak256 } from "ethers";

export const ENS_REGISTRY = "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e";

export function deployUR(foundry: Foundry) {
	return foundry.deploy({
		file: "UR",
		args: [
			ENS_REGISTRY,
			["https://ccip-v2.ens.xyz"], // ens batched gateway service
		],
	});
}

export async function overrideResolver(
	foundry: Foundry,
	node: string,
	address: string
) {
	// https://github.com/foundry-rs/foundry/issues/9743
	const slot = BigInt(solidityPackedKeccak256(["bytes32", "uint256"], [node, 0n]));
	const prev = BigInt(await foundry.provider.getStorage(ENS_REGISTRY, slot));
	await foundry.setStorageValue(ENS_REGISTRY, slot, prev || 0x1);
	await foundry.setStorageValue(ENS_REGISTRY, slot + 1n, address);
}

export function testUR(resolve: Awaited<ReturnType<typeof createResolve>>) {
	test("empty", () => {
		expect(resolve("raffy.eth", [])).resolves.toMatchObject({
			records: [],
			basename: "raffy.eth",
		});
	});

	test("does not exist", () => {
		expect(
			resolve("_dne123", [
				["addr", 60],
				["text", "avatar"],
			])
		).resolves.toMatchObject({
			ok: false
		});
	});

	test("Onchain PRv2: nick.eth", () => {
		expect(
			resolve("nick.eth", [
				["addr", 60],
				["text", "com.github"],
			])
		).resolves.toMatchObject({
			records: [
				{
					offchain: false,
					batched: false,
					result: ["0xb8c2c29ee19d8307cb7255e1cd9cbde883a267d5"],
				},
				{
					offchain: false,
					batched: false,
					result: ["arachnid"],
				},
			],
		});
	});

	test("Onchain PRv3: vitalik.eth", () => {
		expect(
			resolve("vitalik.eth", [
				["addr", 60],
				["text", "url"],
			])
		).resolves.toMatchObject({
			records: [
				{
					offchain: false,
					batched: false,
					result: ["0xd8da6bf26964af9d7eed9e03e53415d37aa96045"],
				},
				{
					offchain: false,
					batched: false,
					result: ["https://vitalik.ca"],
				},
			],
		});
	});

	test("Onchain NFTResolver: moo331.nft-owner.eth", () => {
		expect(
			resolve("moo331.nft-owner.eth", [
				["addr", 60],
				["text", "avatar"],
			])
		).resolves.toMatchObject({
			records: [
				{
					offchain: false,
					batched: false,
					result: ["0x51050ec063d393217b436747617ad1c2285aeeee"],
				},
				{
					offchain: false,
					batched: false,
					result: [
						"eip155:1/erc721:0xe43d741e21d8bf30545a88c46e4ff5681518ebad/0x000000000000000000000000000000000000000000000000000000000000014b",
					],
				},
			],
		});
	});

	test("Origin-restricted Offchain: adraffy.cb.id", () => {
		expect(
			resolve("adraffy.cb.id", [
				["addr", 60],
				["addr", 0],
			])
		).resolves.toMatchObject({
			basename: "cb.id",
			records: [
				{
					offchain: true,
					batched: true,
					result: ["0xc973b97c1f8f9e3b150e2c12d4856a24b3d563cb"],
				},
				{
					offchain: true,
					batched: true,
					result: ["0x00142e6414903e4b24d05132352f71b75c165932a381"],
				},
			],
		});
	});

	test("Origin-restricted Offchain w/Unknown Record: raffy.base.eth", () => {
		expect(
			resolve("raffy.base.eth", [["addr", 60], ["dne"]])
		).resolves.toMatchObject({
			basename: "base.eth",
			records: [
				{
					offchain: true,
					batched: true,
					result: ["0x51050ec063d393217b436747617ad1c2285aeeee"],
				},
				{
					offchain: true,
					batched: true,
					error: true,
				},
			],
		});
	});

	test("TOR(onchain): raffy.eth", () => {
		expect(
			resolve("raffy.eth", [
				["addr", 60],
				["text", "com.twitter"],
			])
		).resolves.toMatchObject({
			records: [
				{
					offchain: false,
					batched: false,
					result: ["0x51050ec063d393217b436747617ad1c2285aeeee"],
				},
				{ offchain: false, batched: false, result: ["adraffy"] },
			],
		});
	});

	test("TOR(hybrid): raffy.eth", () => {
		expect(
			resolve("raffy.eth", [
				["addr", 60],
				["text", "location"],
				["text", "description"],
			])
		).resolves.toMatchObject({
			records: [
				{
					offchain: false,
					batched: false,
					result: ["0x51050ec063d393217b436747617ad1c2285aeeee"],
				},
				{
					offchain: true,
					batched: true,
					result: ["Hello from TheOffchainGateway.js!"],
				},
				{
					offchain: true,
					batched: true,
				},
			],
		});
	});

	test("TOR(offchain): eth.coinbase.tog.raffy.eth", () => {
		expect(
			resolve("eth.coinbase.tog.raffy.eth", [["text", "url"]])
		).resolves.toMatchObject({
			basename: "tog.raffy.eth",
			records: [
				{
					offchain: true,
					batched: true,
					result: ["https://www.coinbase.com/price/eth"],
				},
			],
		});
	});

	test("OffchainDNS => ExtendedDNSResolver: brantly.rocks", () => {
		expect(resolve("brantly.rocks", [["addr", 60]])).resolves.toMatchObject(
			{
				basename: "rocks",
				records: [
					{
						offchain: true,
						batched: true,
						result: [
							"0x000000000000000000000000983110309620d911731ac0932219af06091b6744",
						], // wrong encoding
					},
				],
			}
		);
	});

	test("OffchainDNS => TOR: ezccip.raffy.xyz", () => {
		expect(
			resolve("ezccip.raffy.xyz", [
				["addr", 60],
				["text", "avatar"],
			])
		).resolves.toMatchObject({
			basename: "raffy.xyz",
			records: [
				{
					offchain: true,
					batched: true,
					result: ["0x51050ec063d393217b436747617ad1c2285aeeee"],
				},
				{
					offchain: true,
					batched: true,
					result: ["https://raffy.antistupid.com/ens.jpg"],
				},
			],
		});
	});
}
