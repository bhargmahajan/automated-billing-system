public with sharing class TieredSaaSPricingStrategy implements IPricingStrategy {
    public Decimal calculateCharge(String meterType, Decimal quantity) {
        if (quantity == null || quantity <= 0) return 0.00;

        switch on meterType {
            when 'API_CALLS' {
                if (quantity <= 10000) return 0.00;
                if (quantity <= 100000) return (quantity - 10000) * 0.001;
                return (90000 * 0.001) + ((quantity - 100000) * 0.0005);
            }
            when 'STORAGE_GB' {
                return quantity * 0.05;
            }
            when 'COMPUTE_HOURS' {
                return quantity * 0.15;
            }
            when else {
                return 0.00;
            }
        }
    }
}