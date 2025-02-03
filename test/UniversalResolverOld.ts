// TODO: fix me

import { Foundry } from "@adraffy/blocksmith";
import { deployUR } from "./tests.js";
import { RESOLVER_ABI } from "./UR.js";
import { dnsEncode } from "ethers/hash";
import { reverseName } from "./ens.js";

const foundry = await Foundry.launch({
	fork: process.env.PROVIDER,
	infoLog: true,
});

const UR = await deployUR(foundry);

const UniversalResolverOld = await foundry.deploy({
	file: "UniversalResolverOld",
	args: [UR],
});

console.log(
	await UniversalResolverOld["resolve(bytes,bytes[])"](
		dnsEncode("raffy.eth"),
		[
			RESOLVER_ABI.encodeFunctionData("addr(bytes32)", [
				new Uint8Array(32),
			]),
			RESOLVER_ABI.encodeFunctionData("text(bytes32,string)", [
				new Uint8Array(32),
				"description",
			]),
		],
		{ enableCcipRead: true }
	)
);

console.log(
	await UniversalResolverOld.reverse(
		dnsEncode(reverseName("0x51050ec063d393217B436747617aD1C2285Aeeee"))
	)
);

await foundry.shutdown();
