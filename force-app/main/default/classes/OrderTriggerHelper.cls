public class OrderTriggerHelper {
    public static void handleAfterUpdate(List<Order> newOrders, Map<Id, Order> oldOrderMap) {
        Set<Id> ordersToProcess = new Set<Id>();
        
        for (Order newOrder : newOrders) {
            Order oldOrder = oldOrderMap.get(newOrder.Id);
            
            if (newOrder.Status == 'Activated' && oldOrder.Status != 'Activated') {
                ordersToProcess.add(newOrder.Id);
            }
        }
        
        if (!ordersToProcess.isEmpty()) {
            Database.executeBatch(new InvoiceCreation(ordersToProcess));
        }
    }
}