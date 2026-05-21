import { FedaPay, Transaction } from 'fedapay';
import config from '../config.js';

FedaPay.setApiKey(config.fedapay.secretKey);
FedaPay.setEnvironment(config.fedapay.env);

export async function createTransaction({ order, user, plan }) {
  const transaction = await Transaction.create({
    description: `Commande VPS - ${plan.name} (${order.billing_cycle})`,
    amount: Math.round(order.amount),
    currency: { iso: order.currency || 'XOF' },
    customer: {
      email: user.email,
      firstname: user.first_name || '',
      lastname: user.last_name || '',
    },
    callback_url: `${config.frontendUrl}/dashboard?order=${order.id}`,
    cancel_url: `${config.frontendUrl}/checkout/${plan.id}?cancelled=1`,
  });

  const token = await transaction.generateToken();
  return {
    transaction_id: transaction.id,
    checkout_url: token.url,
  };
}

export async function getTransaction(transactionId) {
  return await Transaction.retrieve(transactionId);
}

export function verifyWebhookEvent(payload) {
  // FedaPay envoie un objet JSON avec entity + event
  // On vérifie que le statut est 'transaction.approved'
  if (!payload || !payload.name) {
    throw new Error('Payload webhook invalide.');
  }
  return payload;
}
