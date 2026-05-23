public class PaymentLink implements Queueable {
	private List<Id> invoiceIds;
    private static final Integer BATCH_LIMIT = 20; // Safe chunk size to avoid Stripe 429 limits
    
    public PaymentLink(List<Id> invoiceIds) {
        this.invoiceIds = invoiceIds;
    }
    
    public void execute(QueueableContext context) {}
}