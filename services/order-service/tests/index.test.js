jest.mock('axios');

const axios = require('axios');
const request = require('supertest');
const app = require('../src/index');

describe('order-service', () => {
  afterEach(() => {
    jest.clearAllMocks();
  });

  test('GET /health returns healthy', async () => {
    const res = await request(app).get('/health');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('healthy');
  });

  test('GET /ready returns ready even if product-service is unreachable', async () => {
    axios.get.mockRejectedValueOnce(new Error('connect ECONNREFUSED'));
    const res = await request(app).get('/ready');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('ready');
  });

  test('GET /orders lists seeded orders', async () => {
    const res = await request(app).get('/orders');
    expect(res.status).toBe(200);
    expect(res.body.count).toBeGreaterThanOrEqual(1);
    expect(res.body.orders.some((o) => o.id === 'ord-001')).toBe(true);
  });

  test('GET /orders?userId filters by user', async () => {
    const res = await request(app).get('/orders?userId=user-001');
    expect(res.status).toBe(200);
    expect(res.body.orders.every((o) => o.userId === 'user-001')).toBe(true);
  });

  test('GET /orders/:orderId returns the order', async () => {
    const res = await request(app).get('/orders/ord-001');
    expect(res.status).toBe(200);
    expect(res.body.id).toBe('ord-001');
  });

  test('GET /orders/:orderId returns 404 for unknown order', async () => {
    const res = await request(app).get('/orders/does-not-exist');
    expect(res.status).toBe(404);
  });

  test('POST /orders rejects missing fields', async () => {
    const res = await request(app).post('/orders').send({ userId: 'user-001' });
    expect(res.status).toBe(400);
  });

  test('POST /orders creates an order when stock is available', async () => {
    axios.get.mockImplementation((url) => {
      if (url.endsWith('/stock')) {
        return Promise.resolve({ data: { stock: 10 } });
      }
      return Promise.resolve({
        data: { id: 'prod-001', name: 'Widget', price: 9.99 },
      });
    });
    axios.post.mockResolvedValue({ data: { message: 'Stock updated' } });

    const res = await request(app)
      .post('/orders')
      .send({
        userId: 'user-002',
        items: [{ productId: 'prod-001', quantity: 2 }],
        shippingAddress: '1 Test Street',
      });

    expect(res.status).toBe(201);
    expect(res.body.userId).toBe('user-002');
    expect(res.body.total).toBeCloseTo(19.98);
    expect(res.body.status).toBe('pending');
  });

  test('POST /orders returns 409 when stock is insufficient', async () => {
    axios.get.mockResolvedValue({ data: { stock: 0 } });

    const res = await request(app)
      .post('/orders')
      .send({ userId: 'user-002', items: [{ productId: 'prod-001', quantity: 5 }] });

    expect(res.status).toBe(409);
  });

  test('POST /orders returns 404 when product does not exist', async () => {
    axios.get.mockRejectedValue({ response: { status: 404 } });

    const res = await request(app)
      .post('/orders')
      .send({ userId: 'user-002', items: [{ productId: 'missing', quantity: 1 }] });

    expect(res.status).toBe(404);
  });

  test('PATCH /orders/:orderId/status updates status', async () => {
    const res = await request(app)
      .patch('/orders/ord-001/status')
      .send({ status: 'shipped' });

    expect(res.status).toBe(200);
    expect(res.body.status).toBe('shipped');
  });

  test('PATCH /orders/:orderId/status rejects invalid status', async () => {
    const res = await request(app)
      .patch('/orders/ord-001/status')
      .send({ status: 'not-a-real-status' });

    expect(res.status).toBe(400);
  });

  test('PATCH /orders/:orderId/status returns 404 for unknown order', async () => {
    const res = await request(app)
      .patch('/orders/does-not-exist/status')
      .send({ status: 'shipped' });

    expect(res.status).toBe(404);
  });

  test('GET /events returns the in-memory event log', async () => {
    const res = await request(app).get('/events');
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body.events)).toBe(true);
  });
});
