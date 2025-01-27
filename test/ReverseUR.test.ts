import { Foundry } from "@adraffy/blocksmith";
import { deployUR, overrideResolver } from "./tests.js";
import { type URLookup } from "./UR.js";
import { test, afterAll, expect } from "bun:test";
import { describe } from "./describe-fix.js";
import { type BigNumberish, dnsEncode, namehash } from "ethers";

function coinTypeFromChain(chain: number) {
	return chain + 0x8000_0000;
}

describe("ReverseUR", async () => {
	const foundry = await Foundry.launch({
		fork: process.env.PROVIDER,
		infoLog: true,
	});
	afterAll(foundry.shutdown);

	const UR = await deployUR(foundry);
	const ReverseUR = await foundry.deploy({ file: "ReverseUR", args: [UR] });

	async function reverse(address: string, coinType: number) {
		const res = await ReverseUR.reverse(address, coinType, [], {
			enableCcipRead: true,
		});
		return {
			rev: res[0].toObject() as URLookup,
			fwd: res[1].toObject() as URLookup,
			answer: res[2] as string,
		};
	}

	const DefaultResolver = await foundry.deploy({
		file: "ExtendedNameResolver",
	});
	await overrideResolver(
		foundry,
		namehash("default.reverse"),
		DefaultResolver.target
	);

	const BASE = 8453;
	const BaseResolver = await foundry.deploy({ file: "ExtendedNameResolver" });
	await overrideResolver(
		foundry,
		namehash(`${coinTypeFromChain(BASE)}.reverse`),
		BaseResolver.target
	);

	const address = "0x51050ec063d393217B436747617aD1C2285Aeeee";
	await foundry.confirm(
		DefaultResolver.set(address.toLowerCase().slice(2), "raffy.eth")
	);

	test(address, () => {
		expect(
			reverse(address, coinTypeFromChain(BASE))
		).resolves.toMatchObject({
			rev: {
				dns: dnsEncode(
					"51050ec063d393217b436747617ad1c2285aeeee.default.reverse"
				),
			},
			fwd: {
				dns: dnsEncode("raffy.eth"),
			},
			answer: address.toLowerCase(),
		});
	});

	// TODO: more tests
});

// function slugFromChain(chain: number) {
// 	switch (chain) {
// 		case 0: return 'default';
// 		case 60: return 'addr';
// 		default: return String(coinTypeFromChain(chain));
// 	}
// }
