import { Foundry } from "@adraffy/blocksmith";
import { deployUR } from "./tests.js";

const foundry = await Foundry.launch({
	fork: process.env.PROVIDER,
	infoLog: true,
});

const UR = await deployUR(foundry);

const UnruggableUR = await foundry.deploy({
	file: "UnruggableUR",
	args: [UR],
});

console.log(
	await UnruggableUR.resolve(
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

// TODO: fix me

await foundry.shutdown();
