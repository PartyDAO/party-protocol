"use strict";
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
var __generator = (this && this.__generator) || function (thisArg, body) {
    var _ = { label: 0, sent: function() { if (t[0] & 1) throw t[1]; return t[1]; }, trys: [], ops: [] }, f, y, t, g;
    return g = { next: verb(0), "throw": verb(1), "return": verb(2) }, typeof Symbol === "function" && (g[Symbol.iterator] = function() { return this; }), g;
    function verb(n) { return function (v) { return step([n, v]); }; }
    function step(op) {
        if (f) throw new TypeError("Generator is already executing.");
        while (_) try {
            if (f = 1, y && (t = op[0] & 2 ? y["return"] : op[0] ? y["throw"] || ((t = y["return"]) && t.call(y), 0) : y.next) && !(t = t.call(y, op[1])).done) return t;
            if (y = 0, t) op = [op[0] & 2, t.value];
            switch (op[0]) {
                case 0: case 1: t = op; break;
                case 4: _.label++; return { value: op[1], done: false };
                case 5: _.label++; y = op[1]; op = [0]; continue;
                case 7: op = _.ops.pop(); _.trys.pop(); continue;
                default:
                    if (!(t = _.trys, t = t.length > 0 && t[t.length - 1]) && (op[0] === 6 || op[0] === 2)) { _ = 0; continue; }
                    if (op[0] === 3 && (!t || (op[1] > t[0] && op[1] < t[3]))) { _.label = op[1]; break; }
                    if (op[0] === 6 && _.label < t[1]) { _.label = t[1]; t = op; break; }
                    if (t && _.label < t[2]) { _.label = t[2]; _.ops.push(op); break; }
                    if (t[2]) _.ops.pop();
                    _.trys.pop(); continue;
            }
            op = body.call(thisArg, _);
        } catch (e) { op = [6, e]; y = 0; } finally { f = t = 0; }
        if (op[0] & 5) throw op[1]; return { value: op[0] ? op[1] : void 0, done: true };
    }
};
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
exports.__esModule = true;
var chai_1 = require("chai");
var ethers_1 = require("ethers");
var ethereum_waffle_1 = require("ethereum-waffle");
var Globals_json_1 = __importDefault(require("../out/Globals.sol/Globals.json"));
(0, chai_1.use)(ethereum_waffle_1.solidity);
describe('Globals test', function () {
    var _a = new ethereum_waffle_1.MockProvider().getWallets(), wallet = _a[0], multisig = _a[1];
    var globalsContract;
    before(function () { return __awaiter(void 0, void 0, void 0, function () {
        return __generator(this, function (_a) {
            switch (_a.label) {
                case 0: return [4 /*yield*/, (0, ethereum_waffle_1.deployContract)(wallet, Globals_json_1["default"], [multisig.address])];
                case 1:
                    globalsContract = _a.sent();
                    return [2 /*return*/];
            }
        });
    }); });
    it('returns zero for unset key', function () { return __awaiter(void 0, void 0, void 0, function () {
        var r;
        return __generator(this, function (_a) {
            switch (_a.label) {
                case 0: return [4 /*yield*/, globalsContract.getUint256(randomKey())];
                case 1:
                    r = _a.sent();
                    (0, chai_1.expect)(r).to.eq(0);
                    return [2 /*return*/];
            }
        });
    }); });
    it('returns set value for set key', function () { return __awaiter(void 0, void 0, void 0, function () {
        var v, k, r;
        return __generator(this, function (_a) {
            switch (_a.label) {
                case 0:
                    v = ethers_1.BigNumber.from('10000000000000000000000000');
                    k = randomKey();
                    return [4 /*yield*/, globalsContract.connect(multisig).setUint256(k, v)];
                case 1:
                    _a.sent();
                    return [4 /*yield*/, globalsContract.getUint256(k)];
                case 2:
                    r = _a.sent();
                    (0, chai_1.expect)(r).to.eq(v);
                    return [2 /*return*/];
            }
        });
    }); });
    it('cannot set value if not multisig', function () { return __awaiter(void 0, void 0, void 0, function () {
        var v, k, tx;
        return __generator(this, function (_a) {
            v = ethers_1.BigNumber.from('10000000000000000000000000');
            k = randomKey();
            tx = globalsContract.setUint256(k, v);
            return [2 /*return*/, (0, chai_1.expect)(tx).to.be.reverted];
        });
    }); });
});
function randomKey() {
    return Math.floor(Math.random() * 1e4);
}
//# sourceMappingURL=Globals.t.js.map