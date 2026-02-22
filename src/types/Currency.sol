// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {CurrencyDelta} from "../libraries/CurrencyDelta.sol";

using {CurrencyDelta.applyDelta} for Currency global;

type Currency is address;
