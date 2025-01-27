import { Foundry } from "@adraffy/blocksmith";
import { serve } from "@resolverworks/ezccip/serve";
import { EZCCIP } from "@resolverworks/ezccip";
import { test, afterAll, expect } from "bun:test";
import { describe } from "./describe-fix.js";

describe("CCIPReader", async () => {
	const foundry = await Foundry.launch({ infoLog: false });
	afterAll(foundry.shutdown);

	const ezccip = new EZCCIP();
	ezccip.register("test() returns (string)", () => ["chonk"]);

	const ccip = await serve(ezccip, { log: false, protocol: "raw" });
	afterAll(ccip.shutdown);

	const Offchain = await foundry.deploy(`
		import {OffchainLookup} from "@src/CCIPReadProtocol.sol";
		contract Offchain {
			string[] gateways = ["${ccip.endpoint}"];
			function test() external view returns (string memory) {
				revert OffchainLookup(address(this), gateways, msg.data, this.testCallback.selector, '');
			}
			function testCallback(bytes memory ccip, bytes memory) external view {
				assembly {
					return(add(ccip, 32), mload(ccip))
				}
			}
		}
	`);

	const Wrapper = await foundry.deploy(`
		import {CCIPReader} from "@src/CCIPReader.sol";
		contract Wrapper is CCIPReader {
			function wrap() external view returns (string memory, string memory) {
				bytes memory v = ccipRead(
					${Offchain.target},
					hex"${Offchain.interface.encodeFunctionData("test", []).slice(2)}", 
					this.wrapCallback.selector,
					abi.encode("CHONK")
				);
				assembly {
					return(add(v, 32), mload(v))
				} 
			}
			function wrapCallback(bytes memory ccip, bytes memory carry) external view returns (string memory, string memory) {
				return (
					abi.decode(ccip, (string)),
					abi.decode(carry, (string))
				);
			}
		}
	`);

	test("Offchain", () =>
		expect(Offchain.test({ enableCcipRead: true })).resolves.toBe("chonk"));

	test("Wrapper", () =>
		expect(
			Wrapper.wrap({ enableCcipRead: true }).then((x) => x.toArray())
		).resolves.toMatchObject(["chonk", "CHONK"]));
});
