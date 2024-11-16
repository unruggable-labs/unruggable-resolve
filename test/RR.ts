import { Foundry } from "@adraffy/blocksmith";


console.log(process.env.PROVIDER);

const foundry = await Foundry.launch({
	fork: process.env.PROVIDER,
	infoLog: true,
});

const RR = await foundry.deploy({
	file: "RR",
	args: [
		"0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e", // ens registry
		["https://ccip-v2.ens.xyz"], // ens batched gateway service
	],
});


console.log(await RR.reverse('0x51050ec063d393217B436747617aD1C2285Aeeee', 60, [], {enableCcipRead: true}));


await foundry.shutdown();