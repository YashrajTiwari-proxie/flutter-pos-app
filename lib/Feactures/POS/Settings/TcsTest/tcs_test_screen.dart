// Dev-only screen for manually testing TCS-D fiscalization against
// Infrasec's verify environment, gated behind a real SoftPay charge —
// exactly the sequence the real checkout will use later: charge succeeds ->
// fiscalize -> show what came back. Never creates a Convex order and never
// touches OrderService/order-lifecycle reporting - this is a standalone
// fiscal-only test, not a real sale.
//
// Deliberately no device pairing/registration flow and no input form - just
// the predefined values below and a single button. Edit the constants
// directly to change what gets tested.
//
// Reuses the existing, unmodified SoftPayService/SoftPayException/
// PaymentStatusUpdate (EmployeeTerminal/softpay_service.dart) exactly as
// EmployeeTerminalScreen does.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kds_pos/Feactures/POS/EmployeeTerminal/error_state.dart';
import 'package:kds_pos/Feactures/POS/EmployeeTerminal/softpay_models.dart';
import 'package:kds_pos/Feactures/POS/EmployeeTerminal/softpay_service.dart';
import 'package:kds_pos/Services/tcs/tcs_formatting.dart';
import 'package:kds_pos/Services/tcs/tcs_models.dart';
import 'package:kds_pos/Services/tcs/tcs_service.dart';

// --- Predefined test values - edit these directly, no in-app form. ---

/// A real, currently-active POS device token — pair a device from the admin
/// dashboard's Devices page and paste its token here (nothing in this file
/// can obtain one on its own; there's no pairing flow in this test build).
const _testDeviceToken = 'PASTE_A_REAL_POS_DEVICE_TOKEN_HERE';

const _testAmountCents = 11626; // 116,26 SEK
const _testVatBasisPoints = 2500; // 25,00%
const _currency = 'SEK';

class TcsTestScreen extends StatefulWidget {
  const TcsTestScreen({super.key});

  @override
  State<TcsTestScreen> createState() => _TcsTestScreenState();
}

enum _Phase { idle, charging, fiscalizing, done }

class _TcsTestScreenState extends State<TcsTestScreen> {
  final _softPay = SoftPayService.instance;
  final _tcs = TcsService.instance;

  _Phase _phase = _Phase.idle;
  PaymentStage? _paymentStage;
  String? _paymentDetail;
  StreamSubscription<PaymentStatusUpdate>? _statusSubscription;

  TransactionResult? _transaction;
  TcsResult? _tcsResult;
  String? _errorMessage;

  bool get _isBusy => _phase == _Phase.charging || _phase == _Phase.fiscalizing;

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }

  Future<void> _runTest() async {
    if (_isBusy) return;

    if (_testDeviceToken == 'PASTE_A_REAL_POS_DEVICE_TOKEN_HERE') {
      setState(() => _errorMessage = 'Set _testDeviceToken at the top of tcs_test_screen.dart first.');
      return;
    }

    setState(() {
      _phase = _Phase.charging;
      _paymentStage = null;
      _paymentDetail = null;
      _transaction = null;
      _tcsResult = null;
      _errorMessage = null;
    });

    _statusSubscription?.cancel();
    _statusSubscription = _softPay.statusUpdates.listen((update) {
      if (!mounted) return;
      setState(() {
        _paymentStage = update.stage;
        _paymentDetail = update.stage == PaymentStage.processing && update.detail != null
            ? friendlySoftPayProcessingUpdate(update.detail!)
            : update.detail;
      });
    });

    final TransactionResult transaction;
    try {
      transaction = await _softPay.charge(amountMinor: _testAmountCents, currency: _currency);
    } on SoftPayException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.idle;
        _errorMessage = e.code == 'CANCELLED' ? 'Payment cancelled.' : friendlySoftPayMessage(e.message);
      });
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.idle;
        _errorMessage = friendlyErrorMessage(e, action: 'processing this test payment');
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _transaction = transaction;
      _phase = _Phase.fiscalizing;
    });

    final split = splitVat(_testAmountCents, _testVatBasisPoints);
    final vats = [
      TcsVatBand(
        percent: formatSwedishAmount(_testVatBasisPoints),
        amount: formatSwedishAmount(split.vatCents),
        subtotalAmount: formatSwedishAmount(split.subtotalCents),
      ),
      const TcsVatBand(percent: '0,00', amount: '0,00', subtotalAmount: '0,00'),
      const TcsVatBand(percent: '0,00', amount: '0,00', subtotalAmount: '0,00'),
      const TcsVatBand(percent: '0,00', amount: '0,00', subtotalAmount: '0,00'),
    ];

    try {
      final result = await _tcs.agentSale(
        deviceToken: _testDeviceToken,
        saleAmount: formatSwedishAmount(_testAmountCents),
        dateTime: nowDateTime14(),
        sequenceNumber: randomSequenceNumber(),
        vats: vats,
      );
      if (!mounted) return;
      setState(() {
        _tcsResult = result;
        _phase = _Phase.done;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = friendlyErrorMessage(e, action: 'fiscalizing this test sale');
        _phase = _Phase.done;
      });
    }
  }

  Future<void> _cancel() async {
    await _softPay.cancelCharge();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TCS Fiscalization Test')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Charges a fixed ${(_testAmountCents / 100).toStringAsFixed(2)} $_currency via '
                'SoftPay sandbox (VAT ${_testVatBasisPoints / 100}%), then immediately sends it '
                'to TCS-D (Infrasec verify environment) as a normal sale. No Convex order is '
                'created — this is fiscal-only.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isBusy ? null : _runTest,
                child: Text(_isBusy ? 'Running…' : 'Charge & Fiscalize'),
              ),
              if (_phase == _Phase.charging) ...[
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _cancel, child: const Text('Cancel payment')),
              ],
              const SizedBox(height: 24),
              _StatusPanel(
                phase: _phase,
                paymentStage: _paymentStage,
                paymentDetail: _paymentDetail,
                transaction: _transaction,
                tcsResult: _tcsResult,
                errorMessage: _errorMessage,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.phase,
    required this.paymentStage,
    required this.paymentDetail,
    required this.transaction,
    required this.tcsResult,
    required this.errorMessage,
  });

  final _Phase phase;
  final PaymentStage? paymentStage;
  final String? paymentDetail;
  final TransactionResult? transaction;
  final TcsResult? tcsResult;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    if (phase == _Phase.idle && transaction == null && tcsResult == null && errorMessage == null) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (phase == _Phase.charging) ...[
              Text('SoftPay: ${paymentStage?.name ?? 'connecting'}'),
              if (paymentDetail != null) Text(paymentDetail!),
            ],
            if (phase == _Phase.fiscalizing) const Text('Payment approved — sending to TCS…'),
            if (transaction != null) ...[
              Text(
                'SoftPay approved: ${(transaction!.amountMinor / 100).toStringAsFixed(2)} '
                '${transaction!.currency} (${transaction!.cardScheme ?? 'card'} '
                '•••${transaction!.partialPan ?? '????'})',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
            ],
            if (tcsResult != null) _TcsResultView(result: tcsResult!),
            if (errorMessage != null)
              Text(errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ),
      ),
    );
  }
}

class _TcsResultView extends StatelessWidget {
  const _TcsResultView({required this.result});

  final TcsResult result;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              result.success ? Icons.check_circle : Icons.error,
              color: result.success ? Colors.green : scheme.error,
            ),
            const SizedBox(width: 8),
            Text(
              result.success ? 'Fiscalized' : 'TCS rejected the request',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _kv('HTTP status', result.httpStatus?.toString()),
        _kv('Response code', result.responseCode),
        _kv('Response reason', result.responseReason),
        _kv('SKV response', result.skvResponseMessage),
        _kv('Control server ID', result.controlServerId),
        _kv('Control code', result.code),
        _kv('Sequence number', result.sequenceNumber),
        _kv('Request ID', result.requestId),
        if (result.error != null) _kv('Network error', result.error),
      ],
    );
  }

  Widget _kv(String label, String? value) {
    if (value == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SelectableText('$label: $value'),
    );
  }
}
