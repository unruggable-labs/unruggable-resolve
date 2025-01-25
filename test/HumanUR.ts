import { Foundry } from "@adraffy/blocksmith";
import { afterAll } from "bun:test";
import { describe } from "./describe-fix.js";
import { deployUR, testUR } from "./tests.js";

const foundry = await Foundry.launch({
	fork: process.env.PROVIDER,
	infoLog: true,
});

const UR = await deployUR(foundry);

const HumanUR = await foundry.deploy({
	file: "HumanUR",
	args: [UR],
});

console.log(
	await HumanUR.resolve(
		"raffy.eth",
		["avatar", "description", "ccip.context"],
		[60, 8444],
		true,
		[],
		{
			enableCcipRead: true,
		}
	)
);

await foundry.shutdown();
