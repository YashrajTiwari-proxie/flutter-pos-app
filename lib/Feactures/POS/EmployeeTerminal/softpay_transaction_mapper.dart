import '../../../Database/models/transaction_snapshot.dart';
import 'softpay_models.dart';

/// Bridges the Softpay SDK's own [TransactionResult] into the shape
/// `posPayments:reportEvent`'s `transaction` arg expects — kept
/// feature-local (not in `Database/models`) since it couples to a
/// Softpay-specific type, not a Convex-mirrored one.
TransactionSnapshot toTransactionSnapshot(TransactionResult transaction) => TransactionSnapshot(
  requestId: transaction.requestId,
  state: transaction.state,
  type: transaction.type,
  cardScheme: transaction.cardScheme,
  partialPan: transaction.partialPan,
  auditNumber: transaction.auditNumber,
  cvm: transaction.cvm,
  terminalId: transaction.terminalId,
  batchNumber: transaction.batchNumber,
  tipMinor: transaction.tipMinor,
  surchargeMinor: transaction.surchargeMinor,
  transactionDate: transaction.transactionDate,
);
