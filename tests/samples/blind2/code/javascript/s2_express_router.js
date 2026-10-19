const router = express.Router();
router.post("/orders", validate, async (req, res) => {
  res.status(201).json(await createOrder(req.body));
});