import { Cl, ClarityType } from "@stacks/transactions";
import { beforeEach, describe, expect, it } from "vitest";
import { ParsedTransactionResult } from "@hirosystems/clarinet-sdk";
import { pnauMainnetVaas, priceFeeds } from "./fixtures";
import { wormhole } from "../wormhole/helpers";

const pythOracleContractName = "pyth-oracle-v4";
const pythDecoderPnauContractName = "pyth-pnau-decoder-v3";
const pythStorageContractName = "pyth-storage-v4";
const wormholeCoreContractName = "wormhole-core-v4";

describe("pyth-oracle-v4::decode-and-verify-price-feeds mainnet VAAs", () => {
  const accounts = simnet.getAccounts();
  const deployer = accounts.get("deployer")!;
  const sender = accounts.get("wallet_1")!;

  let block: ParsedTransactionResult[] | undefined = undefined;

  // Before starting the test suite, we have to setup the guardian set.
  beforeEach(async () => {
    block = wormhole.applyMainnetGuardianSetUpdates(
      deployer,
      wormholeCoreContractName,
    );
  });

  it("should succeed handling the 2 guardians rotations", () => {
    expect(block!).toHaveLength(1);
    block!.forEach((b: ParsedTransactionResult) => {
      expect(b.result).toHaveClarityType(ClarityType.ResponseOk);
    });

    const newUpdateBlock = wormhole.applyNextMainnetGuardianSetUpdates(sender, wormholeCoreContractName)
    expect(newUpdateBlock!).toHaveLength(1);
    newUpdateBlock!.forEach((b: ParsedTransactionResult) => {
      expect(b.result).toHaveClarityType(ClarityType.ResponseOk);
    });
  });

  it("should succeed handling PNAU mainnet payloads", () => {
    const pnauBytes = Cl.bufferFromHex(pnauMainnetVaas[0]);
    let priceIdentifier = Cl.bufferFromHex(
      "ec7a775f46379b5e943c3526b1c8d54cd49749176b0b98e02dde68d1bd335c17",
    );
    let priceUpdated = Cl.tuple({
      "price-identifier": priceIdentifier,
      conf: Cl.uint(37359),
      "ema-conf": Cl.uint(36191),
      "ema-price": Cl.int(46167004),
      expo: Cl.int(-8),
      "prev-publish-time": Cl.uint(1695751648),
      price: Cl.int(46098556),
      "publish-time": Cl.uint(1695751649),
    });
    let executionPlan = Cl.tuple({
      "pyth-storage-contract": Cl.contractPrincipal(
        simnet.deployer,
        pythStorageContractName,
      ),
      "pyth-decoder-contract": Cl.contractPrincipal(
        simnet.deployer,
        pythDecoderPnauContractName,
      ),
      "wormhole-core-contract": Cl.contractPrincipal(
        simnet.deployer,
        wormholeCoreContractName,
      ),
    });

    let res = simnet.callPublicFn(
      pythOracleContractName,
      "verify-and-update-price-feeds",
      [pnauBytes, executionPlan],
      sender,
    ).result;
    expect(res).toBeOk(Cl.list([priceUpdated]));

    res = simnet.callPublicFn(
      pythOracleContractName,
      "read-price-feed",
      [
        priceIdentifier,
        Cl.contractPrincipal(simnet.deployer, pythStorageContractName),
      ],
      sender,
    ).result;
    expect(res).toBeOk(
      Cl.tuple({
        conf: Cl.uint(37359),
        "ema-conf": Cl.uint(36191),
        "ema-price": Cl.int(46167004),
        expo: Cl.int(-8),
        "prev-publish-time": Cl.uint(1695751648),
        price: Cl.int(46098556),
        "publish-time": Cl.uint(1695751649),
      }),
    );
  });
});

describe("pyth-oracle-v4::decode-and-verify-price-feeds mainnet VAAs Multi price updates", () => {
  const accounts = simnet.getAccounts();
  const deployer = accounts.get("deployer")!;
  const sender = accounts.get("wallet_1")!;


  // Before starting the test suite, we have to setup the guardian set.
  beforeEach(async () => {
    let block = wormhole.applyMainnetGuardianSetUpdates(
      deployer,
      wormholeCoreContractName,
    );

    expect(block!).toHaveLength(1);
    block!.forEach((b: ParsedTransactionResult) => {
      expect(b.result).toHaveClarityType(ClarityType.ResponseOk);
    });

    block = wormhole.applyNextMainnetGuardianSetUpdates(sender, wormholeCoreContractName)
    expect(block!).toHaveLength(1);
    block!.forEach((b: ParsedTransactionResult) => {
      expect(b.result).toHaveClarityType(ClarityType.ResponseOk);
    });
  });

  it.each([1, 2, 3, 4, 5, 6])(
    "Should handle price feeds: %i",
    async (idx) => {
      const pnauBytes = Cl.bufferFromHex(priceFeeds[idx - 1]);
      let executionPlan = Cl.tuple({
        "pyth-storage-contract": Cl.contractPrincipal(
          simnet.deployer,
          pythStorageContractName,
        ),
        "pyth-decoder-contract": Cl.contractPrincipal(
          simnet.deployer,
          pythDecoderPnauContractName,
        ),
        "wormhole-core-contract": Cl.contractPrincipal(
          simnet.deployer,
          wormholeCoreContractName,
        ),
      });

      let res = simnet.callPublicFn(
        pythOracleContractName,
        "verify-and-update-price-feeds",
        [pnauBytes, executionPlan],
        sender,
      );
      expect(res.result).toHaveClarityType(ClarityType.ResponseOk);
      expect(res.result.value.list).toHaveLength(idx);
    })
});
